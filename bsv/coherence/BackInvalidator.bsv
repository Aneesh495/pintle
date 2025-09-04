/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/coherence/BackInvalidator.bsv
 * Description: Back-Invalidation (BI) snooper and response aggregator, coordinating
 *              multi-host cache invalidations and dirty writeback capture.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package BackInvalidator;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import CoherenceTypes::*;

typedef struct {
   Bool          active;
   Addr          line_addr;
   SharerMask    pending_mask;
   Bool          has_dirty_data;
   CacheLineData dirty_data;
} BiSlot deriving (Bits, Eq, FShow);

interface BackInvalidator;
   method Action startInvalidation(MshrIdx mshr_id, Addr addr, SharerMask target_mask, Bool need_data);
   method ActionValue#(BackInvalidateReq) getSnoopReq();
   method Action putSnoopRsp(MshrIdx mshr_id, BackInvalidateRsp rsp);
   method ActionValue#(Tuple3#(MshrIdx, Bool, CacheLineData)) getCompletion();
   method Bool isIdle();
endinterface

(* synthesize *)
module mkBackInvalidator (BackInvalidator);
   Vector#(16, Reg#(BiSlot)) bi_slots <- replicateM(mkReg(unpack(0)));

   Reg#(SharerMask) broadcast_mask <- mkReg(0);
   Reg#(MshrIdx)    broadcast_mshr <- mkReg(0);
   Reg#(Addr)       broadcast_addr <- mkReg(0);
   Reg#(Bool)       broadcast_data <- mkReg(False);

   FIFOF#(BackInvalidateReq) snoop_req_fifo <- mkFIFOF();
   FIFOF#(Tuple3#(MshrIdx, Bool, CacheLineData)) completion_fifo <- mkFIFOF();

   rule emit_snoop if (broadcast_mask != 0);
      HostId target_host = 0;
      for (Integer h = 7; h >= 0; h = h - 1) begin
         if (broadcast_mask[h] == 1'b1) target_host = fromInteger(h);
      end
      BackInvalidateReq req = BackInvalidateReq {
         dest_host: target_host,
         tag:       zeroExtend(broadcast_mshr),
         opcode:    broadcast_data ? BI_SNP_DATA : BI_SNP_INV,
         addr:      broadcast_addr
      };
      snoop_req_fifo.enq(req);
      broadcast_mask <= removeSharer(broadcast_mask, target_host);
   endrule

   method Action startInvalidation(MshrIdx mshr_id, Addr addr, SharerMask target_mask, Bool need_data) if (broadcast_mask == 0);
      BiSlot slot = BiSlot {
         active:         True,
         line_addr:      addr,
         pending_mask:   target_mask,
         has_dirty_data: False,
         dirty_data:     0
      };
      bi_slots[mshr_id] <= slot;

      broadcast_mask <= target_mask;
      broadcast_mshr <= mshr_id;
      broadcast_addr <= addr;
      broadcast_data <= need_data;
   endmethod

   method ActionValue#(BackInvalidateReq) getSnoopReq();
      snoop_req_fifo.deq();
      return snoop_req_fifo.first();
   endmethod

   method Action putSnoopRsp(MshrIdx mshr_id, BackInvalidateRsp rsp);
      let slot = bi_slots[mshr_id];
      if (slot.active) begin
         SharerMask updated_mask = removeSharer(slot.pending_mask, rsp.src_host);
         Bool dirty = slot.has_dirty_data || rsp.has_dirty_data;
         CacheLineData d = rsp.has_dirty_data ? rsp.dirty_data : slot.dirty_data;

         slot.pending_mask   = updated_mask;
         slot.has_dirty_data = dirty;
         slot.dirty_data     = d;

         if (updated_mask == 0) begin
            slot.active = False;
            completion_fifo.enq(tuple3(mshr_id, dirty, d));
         end
         bi_slots[mshr_id] <= slot;
      end
   endmethod

   method ActionValue#(Tuple3#(MshrIdx, Bool, CacheLineData)) getCompletion();
      completion_fifo.deq();
      return completion_fifo.first();
   endmethod

   method Bool isIdle();
      return (broadcast_mask == 0);
   endmethod
endmodule

endpackage: BackInvalidator
