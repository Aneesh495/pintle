/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/top/PintleMemoryPool.bsv
 * Description: Top-level CXL 3.1 Type 3 Coherent Memory Expansion Controller
 *              integrating 256B flit link layer, directory cache coherence,
 *              bank-interleaved DDR5 scheduler, SECDED ECC, and hardware accelerators.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package PintleMemoryPool;

import FIFO::*;
import FIFOF::*;
import Vector::*;

import CxlTypes::*;
import AxiTypes::*;
import Ddr5Types::*;
import CoherenceTypes::*;

import Crc32C::*;
import FlitUnpacker::*;
import FlitPacker::*;
import CreditFlowCtrl::*;
import RetryBuffer::*;

import CoherenceEngine::*;
import AddrMapper::*;
import Ddr5Scheduler::*;
import EccSecDed::*;
import MemScrubber::*;

import Lz4Decompress::*;
import AesGcmCore::*;
import StreamFilter::*;

import PmuCounters::*;
import ThermalGovernor::*;
import CxlCsrBank::*;

interface PintleMemoryPool;
   // CXL Link Layer Interface
   method Action putFlitRx(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getFlitTx();

   // AXI4-Lite Management and CSR Slave Interface
   interface AxiLiteSlave axiSlave;

   // DDR5 SDRAM PHY Interface
   method ActionValue#(Tuple3#(Ddr5Cmd, GlobalBankIdx, RowAddr)) getDdr5Cmd();
   method Action putDdr5ReadData(Bit#(12) req_id, Bit#(512) data, Bit#(64) ecc);

   // Streaming Hardware Offload Interfaces
   method Action putLz4InputByte(Bit#(8) b, Bool is_last);
   method ActionValue#(Tuple2#(Bit#(8), Bool)) getLz4OutputByte();

   method Action putFilterLine(Bit#(512) cacheline);
   method ActionValue#(Bit#(8)) getFilterMatchMask();

   // Status and Telemetry
   method Bool isLinkReady();
   method Bool isThrottled();
   method Bool isCritical();
   method Bit#(64) getMemBaseAddress();
endinterface

(* synthesize *)
module mkPintleMemoryPool (PintleMemoryPool);
   // Subsystems
   // 1. Link Layer
   FlitUnpacker        unpacker    <- mkFlitUnpacker;
   FlitPacker          packer      <- mkFlitPacker;
   CreditFlowControl   credit_ctrl <- mkCreditFlowControl;
   RetryBuffer         retry_buf   <- mkRetryBuffer;

   // 2. Coherence Engine
   CoherenceEngine     coh_engine  <- mkCoherenceEngine;

   // 3. Memory Subsystem
   AddrMapper          addr_mapper <- mkAddrMapper;
   Ddr5TimingConfig    timings     = defaultDdr5Timings();
   Ddr5Scheduler       ddr5_sched  <- mkDdr5Scheduler(timings);
   MemScrubber         scrubber    <- mkMemScrubber;

   // 4. Hardware Offload Subsystem
   Lz4Decompressor     lz4_engine  <- mkLz4Decompressor;
   StreamFilter        filter_core <- mkStreamFilter;

   // 5. Management & CSR Bank
   CxlCsrBank          csr_bank    <- mkCxlCsrBank;

   // Internal FIFOs
   FIFOF#(CxlStandardFlit) flit_rx_fifo <- mkFIFOF;
   FIFOF#(CxlStandardFlit) flit_tx_fifo <- mkFIFOF;

   // MSHR mapping table for DDR5 memory requests (maps Ddr5 req_id back to MshrIdx)
   Vector#(16, Reg#(MshrIdx)) mshr_req_map  <- replicateM(mkReg(0));
   Vector#(16, Reg#(Bool))    mshr_is_write <- replicateM(mkReg(False));

   // State tracking
   Reg#(Bool)          r_link_up    <- mkReg(True);
   Reg#(Bit#(12))      r_tag_alloc  <- mkReg(0);

   // -------------------------------------------------------------------
   // Ingress Link Processing: Rx Flits -> Unpacker -> Coherence Engine
   // -------------------------------------------------------------------
   rule rl_process_rx_flit;
      let flit = flit_rx_fifo.first; flit_rx_fifo.deq;

      // PMU Event
      csr_bank.incrementPmu(PMU_EVT_FLIT_RX);

      // Verify CRC-32C
      let computed_crc = computeFlitCrc(flit);
      $display("[Pool] Rx Flit: computed_crc=0x%08X, flit.crc=0x%08X", computed_crc, flit.crc);
      if (computed_crc == flit.crc) begin
         unpacker.putFlit(flit);
         credit_ctrl.releaseRxBuffers(1);
      end else begin
         $display("[Pool] CRC MISMATCH in Rx Flit!");
      end
   endrule

   rule rl_route_unpacked_mem_req;
      let req_tuple <- unpacker.getMemReq();
      let req  = tpl_1(req_tuple);
      let data = tpl_2(req_tuple);
      coh_engine.putRequest(req, data);
   endrule

   // -------------------------------------------------------------------
   // Coherence to Memory Pipeline: Miss / Eviction -> DDR5 Scheduler
   // -------------------------------------------------------------------
   rule rl_dispatch_coherence_to_ddr5;
      let cmd_tuple <- coh_engine.getMemCmd();
      let mshr_id   = tpl_1(cmd_tuple);
      let addr      = tpl_2(cmd_tuple);
      let is_write  = tpl_3(cmd_tuple);
      $display("[Pool] Coherence Engine -> DDR5: mshr=%0d, addr=0x%016X, write=%b", mshr_id, addr, is_write);

      Bit#(12) tag = r_tag_alloc;
      r_tag_alloc <= r_tag_alloc + 1;
      mshr_req_map[tag[3:0]]  <= mshr_id;
      mshr_is_write[tag[3:0]] <= is_write;

      CxlMemM2SReq dummy_req;
      dummy_req.opcode      = is_write ? MEM_OP_WRITE : MEM_OP_READ;
      dummy_req.tag         = tag;
      dummy_req.addr        = addr;
      dummy_req.byte_en     = 64'hFFFF_FFFF_FFFF_FFFF;
      dummy_req.host_id     = 0;
      dummy_req.port_id     = 0;
      dummy_req.is_prefetch = False;

      let ddr5_req = addr_mapper.mapRequest(dummy_req, 0);
      ddr5_sched.putRequest(ddr5_req);

      if (is_write) begin
         csr_bank.incrementPmu(PMU_EVT_MEM_WRITE);
      end else begin
         csr_bank.incrementPmu(PMU_EVT_MEM_READ);
      end
   endrule

   // -------------------------------------------------------------------
   // DDR5 Memory Return Pipeline -> Coherence Engine Completion
   // -------------------------------------------------------------------
   rule rl_ddr5_return_to_coherence;
      let ddr5_rsp <- ddr5_sched.getResponse();
      let mshr_id = mshr_req_map[ddr5_rsp.req_id[3:0]];
      let was_write = mshr_is_write[ddr5_rsp.req_id[3:0]];

      if (was_write) begin
         coh_engine.putMemWriteAck(mshr_id);
      end else begin
         coh_engine.putMemReadData(mshr_id, ddr5_rsp.read_data);
      end
   endrule

   // -------------------------------------------------------------------
   // Back-Invalidation Snoop Routing: Coherence Engine -> Link Egress
   // -------------------------------------------------------------------
   rule rl_route_snoop_to_link;
      let snoop <- coh_engine.getSnoopOut();
      csr_bank.incrementPmu(PMU_EVT_BI_SNOOP);
      // Auto-acknowledge snoop in memory pool controller loopback
      BackInvalidateRsp bi_rsp;
      bi_rsp.src_host = snoop.dest_host;
      bi_rsp.tag = snoop.tag;
      bi_rsp.status = BI_RSP_CLEAN;
      bi_rsp.has_dirty_data = False;
      bi_rsp.dirty_data = 0;
      MshrIdx mshr_id = snoop.tag[3:0];
      coh_engine.putSnoopIn(mshr_id, bi_rsp);
   endrule

   // -------------------------------------------------------------------
   // Egress Response Pipeline: Coherence Engine -> Flit Packer -> Tx
   // -------------------------------------------------------------------
   rule rl_coherence_rsp_to_packer;
      let rsp <- coh_engine.getResponse();
      packer.putMemRsp(rsp);
   endrule

   rule rl_packer_to_tx_fifo;
      let flit <- packer.getFlit();
      flit_tx_fifo.enq(flit);
      csr_bank.incrementPmu(PMU_EVT_FLIT_TX);
   endrule

   // -------------------------------------------------------------------
   // External Interface Methods
   // -------------------------------------------------------------------
   method Action putFlitRx(CxlStandardFlit flit);
      flit_rx_fifo.enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getFlitTx();
      flit_tx_fifo.deq;
      return flit_tx_fifo.first;
   endmethod

   interface AxiLiteSlave axiSlave = csr_bank.axiSlave;

   method ActionValue#(Tuple3#(Ddr5Cmd, GlobalBankIdx, RowAddr)) getDdr5Cmd();
      let cmd <- ddr5_sched.getIssuedCommand();
      return cmd;
   endmethod

   method Action putDdr5ReadData(Bit#(12) req_id, Bit#(512) data, Bit#(64) ecc);
      ddr5_sched.putPhyReadData(req_id, data, ecc);
   endmethod

   method Action putLz4InputByte(Bit#(8) b, Bool is_last);
      lz4_engine.putInputByte(b, is_last);
   endmethod

   method ActionValue#(Tuple2#(Bit#(8), Bool)) getLz4OutputByte();
      let out <- lz4_engine.getOutputByte();
      return out;
   endmethod

   method Action putFilterLine(Bit#(512) cacheline);
      filter_core.putLine(cacheline);
   endmethod

   method ActionValue#(Bit#(8)) getFilterMatchMask();
      let res <- filter_core.getMatchMask();
      return res;
   endmethod

   method Bool isLinkReady();
      return r_link_up;
   endmethod

   method Bool isThrottled();
      return csr_bank.isThrottled();
   endmethod

   method Bool isCritical();
      return csr_bank.isCritical();
   endmethod

   method Bit#(64) getMemBaseAddress();
      return csr_bank.getMemBaseAddress();
   endmethod
endmodule

endpackage: PintleMemoryPool
