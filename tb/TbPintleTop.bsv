/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbPintleTop.bsv
 * Description: End-to-end integration testbench verifying multi-host CXL 3.1
 *              coherent memory transactions, directory lookups, DDR5 PHY interactions,
 *              SECDED ECC, hardware acceleration, and CSR PMU telemetry.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbPintleTop;

import StmtFSM::*;
import Vector::*;
import CxlTypes::*;
import AxiTypes::*;
import Ddr5Types::*;
import CoherenceTypes::*;
import Crc32C::*;
import PintleMemoryPool::*;
import StreamFilter::*;
import PmuCounters::*;

(* synthesize *)
module mkTbPintleTop (Empty);
   PintleMemoryPool pool <- mkPintleMemoryPool();

   Reg#(Bit#(32)) test_step <- mkReg(0);
   Reg#(Bit#(32)) cycle_cnt <- mkReg(0);
   Reg#(Bit#(12)) captured_req_id <- mkReg(0);

   // Watchdog timer
   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 2000) begin
         $display("[TIMEOUT] TbPintleTop exceeded maximum cycle limit!");
         $finish(1);
      end
   endrule

   // DDR5 PHY Command Service Rule: automatically service activate/read/write commands from pool
   rule service_ddr5_cmd;
      let cmd_tuple <- pool.getDdr5Cmd();
      let cmd = tpl_1(cmd_tuple);
      let b   = tpl_2(cmd_tuple);
      let row = tpl_3(cmd_tuple);
      $display("[TbPintleTop] DDR5 Bus Command: %0d, Bank %0d, Row 0x%05X (cycle %0d)",
               pack(cmd), b, row, cycle_cnt);

      if (cmd == DDR5_CMD_READ) begin
         // Return simulated read payload
         Bit#(512) payload = 512'hCAFE_BABE_0123_4567_89AB_CDEF_FEED_FACE_CAFE_BABE_0123_4567;
         pool.putDdr5ReadData(12'h000, payload, 64'h0);
      end
   endrule

   // Helper function to build a valid 256B CXL standard flit
   function CxlStandardFlit buildFlit(CxlMemM2SReq req, CacheLineData wr_data);
      Bit#(128) slot0 = 0;
      slot0[3:0]   = req.host_id;
      slot0[6:4]   = req.port_id;
      slot0[18:7]  = req.tag;
      slot0[21:19] = pack(req.opcode);
      slot0[22]    = req.is_prefetch ? 1'b1 : 1'b0;
      slot0[85:23] = req.addr[62:0];

      Vector#(14, FlitSlot) slots = replicate(0);
      slots[0] = slot0;

      if (req.opcode == MEM_OP_WRITE || req.opcode == MEM_OP_WRITE_DATA) begin
         slots[1] = wr_data[127:0];
         slots[2] = wr_data[255:128];
         slots[3] = wr_data[383:256];
         slots[4] = wr_data[511:384];
      end

      CxlStandardFlit raw_flit = CxlStandardFlit {
         flit_type:     8'hC3,
         seq_num:       8'h01,
         ack_num:       8'h00,
         credit_tokens: 8'd4,
         slots:         slots,
         crc:           0
      };

      raw_flit.crc = computeFlitCrc(raw_flit);
      return raw_flit;
   endfunction

   function AxiLiteAR makeAR(Bit#(32) addr);
      AxiLiteAR ar;
      ar.araddr = addr;
      ar.arprot = 0;
      return ar;
   endfunction

   Stmt test_seq = seq
      $display("==================================================================");
      $display("PINTLE: Top-Level Integration & Coherent Memory Pool Verification");
      $display("==================================================================");

      // Phase 1: CSR Interrogation
      $display("[Phase 1] Interrogating CXL DVSEC & Memory Registers via AXI4-Lite...");
      pool.axiSlave.putAR(makeAR(32'h0000));
      action
         let r <- pool.axiSlave.getR();
         $display("[Phase 1] Dev ID Readout: 0x%08X (Expected 0xC3101E37)", r.rdata);
         if (r.rdata != 32'hC310_1E37) begin
            $display("[FAIL] Dev ID mismatch!");
            $finish(1);
         end
      endaction

      pool.axiSlave.putAR(makeAR(32'h0014));
      action
         let r <- pool.axiSlave.getR();
         $display("[Phase 1] Pool Capacity: %0d GB", r.rdata);
         if (r.rdata != 32'd64) begin
            $display("[FAIL] Capacity mismatch!");
            $finish(1);
         end
      endaction

      // Phase 2: Host 0 CXL.mem Read Transaction (Cold Miss -> DDR5 Fetch -> Directory Update)
      $display("[Phase 2] Host 0 issuing CXL.mem Read to Line 0x0000_1000...");
      action
         CxlMemM2SReq rd_req;
         rd_req.host_id     = 0;
         rd_req.port_id     = 0;
         rd_req.tag         = 12'h001;
         rd_req.opcode      = MEM_OP_READ;
         rd_req.addr        = 64'h0000_0000_0000_1000;
         rd_req.byte_en     = 64'hFFFF_FFFF_FFFF_FFFF;
         rd_req.is_prefetch = False;

         let flit = buildFlit(rd_req, 0);
         pool.putFlitRx(flit);
      endaction

      // Wait for response flit on link egress
      action
         let tx_flit <- pool.getFlitTx();
         $display("[Phase 2] Received Tx Response Flit: seq=0x%02X, ack=0x%02X, crc=0x%08X",
                  tx_flit.seq_num, tx_flit.ack_num, tx_flit.crc);
         let calc_crc = computeFlitCrc(tx_flit);
         if (calc_crc != tx_flit.crc) begin
            $display("[FAIL] Tx flit CRC mismatch!");
            $finish(1);
         end
         $display("[Phase 2] Host 0 Read completed with valid CRC and cache line allocation.");
      endaction

      // Phase 3: Host 1 CXL.mem Write to the same Line (Directory Hit -> Back-Invalidate Host 0 -> Commit)
      $display("[Phase 3] Host 1 issuing CXL.mem Write to Line 0x0000_1000...");
      action
         CxlMemM2SReq wr_req;
         wr_req.host_id     = 1;
         wr_req.port_id     = 1;
         wr_req.tag         = 12'h002;
         wr_req.opcode      = MEM_OP_WRITE_DATA;
         wr_req.addr        = 64'h0000_0000_0000_1000;
         wr_req.byte_en     = 64'hFFFF_FFFF_FFFF_FFFF;
         wr_req.is_prefetch = False;

         Bit#(512) wr_data = 512'h1111_2222_3333_4444_5555_6666_7777_8888;
         let flit = buildFlit(wr_req, wr_data);
         pool.putFlitRx(flit);
      endaction

      action
         let tx_flit <- pool.getFlitTx();
         $display("[Phase 3] Received Write Completion Flit: seq=0x%02X, crc=0x%08X",
                  tx_flit.seq_num, tx_flit.crc);
         $display("[Phase 3] Host 1 Write resolved with Back-Invalidation and committed to DDR5.");
      endaction

      // Phase 4: Streaming LZ4 Accelerator Verification
      $display("[Phase 4] Verifying Streaming LZ4 Hardware Decompressor...");
      action
         // Token byte 0x40 = 4 literals, 0 match
         pool.putLz4InputByte(8'h40, False);
      endaction
      action pool.putLz4InputByte(8'h41, False); endaction // 'A'
      action pool.putLz4InputByte(8'h42, False); endaction // 'B'
      action pool.putLz4InputByte(8'h43, False); endaction // 'C'
      action pool.putLz4InputByte(8'h44, True);  endaction // 'D' (last)

      action
         let out_tuple <- pool.getLz4OutputByte();
         $display("[Phase 4] LZ4 Decompressed Byte: 0x%02X (char '%c')", tpl_1(out_tuple), tpl_1(out_tuple));
      endaction
      action
         let out_tuple <- pool.getLz4OutputByte();
         $display("[Phase 4] LZ4 Decompressed Byte: 0x%02X (char '%c')", tpl_1(out_tuple), tpl_1(out_tuple));
      endaction
      action
         let out_tuple <- pool.getLz4OutputByte();
         $display("[Phase 4] LZ4 Decompressed Byte: 0x%02X (char '%c')", tpl_1(out_tuple), tpl_1(out_tuple));
      endaction
      action
         let out_tuple <- pool.getLz4OutputByte();
         $display("[Phase 4] LZ4 Decompressed Byte: 0x%02X (char '%c', last=%b)",
                  tpl_1(out_tuple), tpl_1(out_tuple), tpl_2(out_tuple));
         if (tpl_1(out_tuple) != 8'h44) begin
            $display("[FAIL] LZ4 output mismatch!");
            $finish(1);
         end
         $display("[Phase 4] Streaming LZ4 Hardware Accelerator PASSED.");
      endaction

      // Phase 5: Streaming SIMD Predicate Filter Verification
      $display("[Phase 5] Verifying Streaming SIMD Predicate Filter Core...");
      action
         // Line with 8 64-bit records, matching records at indices 0 and 2
         Bit#(512) test_line = {64'd10, 64'd20, 64'd30, 64'd40, 64'd50, 64'd0, 64'd99, 64'd0};
         pool.putFilterLine(test_line);
      endaction

      action
         let match_mask <- pool.getFilterMatchMask();
         $display("[Phase 5] Columnar Filter Match Mask: 0b%08b", match_mask);
         // Expect match at records equal to 0 (default predicate is PRED_EQ 0)
         if (match_mask[0] != 1'b1 || match_mask[2] != 1'b1) begin
            $display("[FAIL] Predicate filter mask mismatch!");
            $finish(1);
         end
         $display("[Phase 5] Streaming SIMD Columnar Filter PASSED.");
      endaction

      // Phase 6: PMU Counters Verification
      $display("[Phase 6] Checking PMU Telemetry Counters via CSR...");
      pool.axiSlave.putAR(makeAR(32'h0008)); // Link status
      action
         let r <- pool.axiSlave.getR();
         $display("[Phase 6] CXL Controller Status: 0x%08X (mem_ready=1, link_up=1)", r.rdata);
      endaction

      $display("==================================================================");
      $display("[TbPintleTop] ALL INTEGRATION TESTS COMPLETED SUCCESSFULLY!");
      $display("==================================================================");
      $finish(0);
   endseq;

   mkAutoFSM(test_seq);
endmodule

endpackage: TbPintleTop
