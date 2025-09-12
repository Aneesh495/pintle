/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/coherence/CoherenceEngine.bsv
 * Description: Master cache coherence coordinator integrating Directory, MSHR
 *              hazard table, Back-Invalidation engine, and DDR5 memory interface.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CoherenceEngine;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import CoherenceTypes::*;
import CacheDirectory::*;
import ConflictTable::*;
import BackInvalidator::*;
import BiasEngine::*;

interface CoherenceEngine;
   method Action putRequest(CxlMemM2SReq req, CacheLineData wr_payload);
   method ActionValue#(CxlMemS2MRsp) getResponse();

   // Interface to Memory Subsystem
   method ActionValue#(Tuple3#(MshrIdx, Addr, Bool)) getMemCmd(); // (mshr, addr, is_write)
   method Action putMemReadData(MshrIdx mshr_id, CacheLineData data);
   method Action putMemWriteAck(MshrIdx mshr_id);

   // Interface to Physical Link for Back-Invalidation Snooping
   method ActionValue#(BackInvalidateReq) getSnoopOut();
   method Action putSnoopIn(MshrIdx mshr_id, BackInvalidateRsp rsp);
endinterface

(* synthesize *)
module mkCoherenceEngine (CoherenceEngine);
   CacheDirectory   dir            <- mkCacheDirectory();
   ConflictTable    conflict_table <- mkConflictTable();
   BackInvalidator  bi_engine      <- mkBackInvalidator();
   BiasEngine       bias_engine    <- mkBiasEngine();

   FIFOF#(Tuple2#(CxlMemM2SReq, CacheLineData)) req_in_fifo  <- mkFIFOF();
   FIFOF#(CxlMemS2MRsp)                         rsp_out_fifo <- mkFIFOF();
   FIFOF#(Tuple3#(MshrIdx, Addr, Bool))         mem_cmd_fifo <- mkFIFOF();

   // Step 1: Process incoming request and allocate MSHR slot
   rule schedule_request if (conflict_table.canAllocate());
      let req_tuple = req_in_fifo.first();
      let req = tpl_1(req_tuple);
      let payload = tpl_2(req_tuple);

      // Hazard check: stall if an active transaction to this cache line exists
      if (!conflict_table.hasConflict(req.addr)) begin
         let match_res = dir.lookup(req.addr);
         Bool hit = tpl_1(match_res);
         DirectoryEntry dir_entry = tpl_2(match_res);

         Bool is_write = (req.opcode == MEM_OP_WRITE || req.opcode == MEM_OP_WRITE_DATA || req.opcode == MEM_OP_INV);

         if (is_write) begin
            SharerMask other_sharers = removeSharer(dir_entry.sharers, req.host_id);
            if (hit && hasSharers(other_sharers)) begin
               let maybe_mshr <- conflict_table.allocate(req, MSHR_WAIT_BI_RSP, payload, other_sharers);
               if (isValid(maybe_mshr)) begin
                  req_in_fifo.deq();
                  MshrIdx mshr_id = fromMaybe(0, maybe_mshr);
                  bi_engine.startInvalidation(mshr_id, req.addr, other_sharers, (dir_entry.state == COH_MODIFIED));
               end
            end else begin
               // No peer invalidation needed, issue write directly to memory
               let maybe_mshr <- conflict_table.allocate(req, MSHR_MEM_WRITE, payload, 0);
               if (isValid(maybe_mshr)) begin
                  req_in_fifo.deq();
                  MshrIdx mshr_id = fromMaybe(0, maybe_mshr);
                  mem_cmd_fifo.enq(tuple3(mshr_id, req.addr, True));

                  DirectoryEntry updated_dir = DirectoryEntry {
                     valid:          True,
                     tag:            req.addr[63:32],
                     state:          COH_MODIFIED,
                     sharers:        (8'b1 << req.host_id),
                     owner:          req.host_id,
                     is_device_bias: False
                  };
                  dir.update(req.addr, updated_dir);
               end
            end
         end else begin
            // Read Request
            if (hit && dir_entry.state == COH_MODIFIED && dir_entry.owner != req.host_id) begin
               SharerMask target = 8'b1 << dir_entry.owner;
               let maybe_mshr <- conflict_table.allocate(req, MSHR_WAIT_BI_RSP, payload, target);
               if (isValid(maybe_mshr)) begin
                  req_in_fifo.deq();
                  MshrIdx mshr_id = fromMaybe(0, maybe_mshr);
                  bi_engine.startInvalidation(mshr_id, req.addr, target, True);
               end
            end else begin
               let maybe_mshr <- conflict_table.allocate(req, MSHR_MEM_READ, payload, 0);
               if (isValid(maybe_mshr)) begin
                  req_in_fifo.deq();
                  MshrIdx mshr_id = fromMaybe(0, maybe_mshr);
                  mem_cmd_fifo.enq(tuple3(mshr_id, req.addr, False));

                  DirectoryEntry updated_dir = DirectoryEntry {
                     valid:          True,
                     tag:            req.addr[63:32],
                     state:          COH_SHARED,
                     sharers:        addSharer(dir_entry.sharers, req.host_id),
                     owner:          dir_entry.owner,
                     is_device_bias: False
                  };
                  dir.update(req.addr, updated_dir);
               end
            end
         end
      end
   endrule

   // Step 2: Handle completion of Back-Invalidations
   rule handle_bi_completion;
      let bi_res <- bi_engine.getCompletion();
      MshrIdx mshr_id = tpl_1(bi_res);
      Bool had_dirty = tpl_2(bi_res);
      CacheLineData dirty_data = tpl_3(bi_res);

      let entry = conflict_table.getEntry(mshr_id);
      if (had_dirty) begin
         entry.line_data = dirty_data;
      end

      if (entry.req_op == MEM_OP_WRITE || entry.req_op == MEM_OP_WRITE_DATA) begin
         entry.phase = MSHR_MEM_WRITE;
         conflict_table.updateEntry(mshr_id, entry);
         mem_cmd_fifo.enq(tuple3(mshr_id, entry.addr, True));

         DirectoryEntry updated_dir = DirectoryEntry {
            valid:          True,
            tag:            entry.addr[63:32],
            state:          COH_MODIFIED,
            sharers:        (8'b1 << entry.req_host),
            owner:          entry.req_host,
            is_device_bias: False
         };
         dir.update(entry.addr, updated_dir);
      end else begin
         // Read completed with dirty snoop writeback data
         CxlMemS2MRsp rsp = CxlMemS2MRsp {
            host_id:  entry.req_host,
            port_id:  0,
            tag:      entry.req_tag,
            status:   RSP_SUCCESS,
            has_data: True,
            data:     entry.line_data
         };
         rsp_out_fifo.enq(rsp);
         conflict_table.releaseEntry(mshr_id);
      end
   endrule

   method Action putRequest(CxlMemM2SReq req, CacheLineData wr_payload);
      req_in_fifo.enq(tuple2(req, wr_payload));
   endmethod

   method ActionValue#(CxlMemS2MRsp) getResponse();
      rsp_out_fifo.deq();
      return rsp_out_fifo.first();
   endmethod

   method ActionValue#(Tuple3#(MshrIdx, Addr, Bool)) getMemCmd();
      mem_cmd_fifo.deq();
      return mem_cmd_fifo.first();
   endmethod

   method Action putMemReadData(MshrIdx mshr_id, CacheLineData data);
      let entry = conflict_table.getEntry(mshr_id);
      CxlMemS2MRsp rsp = CxlMemS2MRsp {
         host_id:  entry.req_host,
         port_id:  0,
         tag:      entry.req_tag,
         status:   RSP_SUCCESS,
         has_data: True,
         data:     data
      };
      rsp_out_fifo.enq(rsp);
      conflict_table.releaseEntry(mshr_id);
   endmethod

   method Action putMemWriteAck(MshrIdx mshr_id);
      let entry = conflict_table.getEntry(mshr_id);
      CxlMemS2MRsp rsp = CxlMemS2MRsp {
         host_id:  entry.req_host,
         port_id:  0,
         tag:      entry.req_tag,
         status:   RSP_SUCCESS,
         has_data: False,
         data:     0
      };
      rsp_out_fifo.enq(rsp);
      conflict_table.releaseEntry(mshr_id);
   endmethod

   method ActionValue#(BackInvalidateReq) getSnoopOut();
      let snoop <- bi_engine.getSnoopReq();
      return snoop;
   endmethod

   method Action putSnoopIn(MshrIdx mshr_id, BackInvalidateRsp rsp);
      bi_engine.putSnoopRsp(mshr_id, rsp);
   endmethod
endmodule

endpackage: CoherenceEngine
