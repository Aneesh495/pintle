/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/accel/StreamFilter.bsv
 * Description: SIMD in-memory predicate evaluator and columnar filter engine,
 *              filtering 8 64-bit records per cycle directly in the memory pool.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package StreamFilter;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;

typedef enum {
   PRED_EQ,
   PRED_NEQ,
   PRED_LT,
   PRED_LE,
   PRED_GT,
   PRED_GE,
   PRED_BETWEEN
} PredicateOp deriving (Bits, Eq, FShow);

typedef struct {
   PredicateOp opcode;
   Bit#(64)    threshold_low;
   Bit#(64)    threshold_high;
} ColumnPredicate deriving (Bits, Eq, FShow);

interface StreamFilter;
   method Action setPredicate(ColumnPredicate p);
   method Action putLine(Bit#(512) cacheline);
   method ActionValue#(Bit#(8)) getMatchMask();
endinterface

(* synthesize *)
module mkStreamFilter (StreamFilter);
   Reg#(ColumnPredicate) active_pred <- mkReg(ColumnPredicate{opcode: PRED_EQ, threshold_low: 0, threshold_high: 0});

   FIFOF#(Bit#(512)) in_line_fifo <- mkFIFOF();
   FIFOF#(Bit#(8))   out_mask_fifo <- mkFIFOF();

   function Bool evalCondition(Bit#(64) val, ColumnPredicate p);
      case (p.opcode)
         PRED_EQ:      return (val == p.threshold_low);
         PRED_NEQ:     return (val != p.threshold_low);
         PRED_LT:      return (val < p.threshold_low);
         PRED_LE:      return (val <= p.threshold_low);
         PRED_GT:      return (val > p.threshold_low);
         PRED_GE:      return (val >= p.threshold_low);
         PRED_BETWEEN: return (val >= p.threshold_low && val <= p.threshold_high);
      endcase
   endfunction

   rule evaluate_line;
      let line = in_line_fifo.first();
      in_line_fifo.deq();

      Bit#(8) mask = 0;
      for (Integer w = 0; w < 8; w = w + 1) begin
         Bit#(64) col_val = line[w * 64 + 63 : w * 64];
         if (evalCondition(col_val, active_pred)) begin
            mask[w] = 1'b1;
         end
      end
      out_mask_fifo.enq(mask);
   endrule

   method Action setPredicate(ColumnPredicate p);
      active_pred <= p;
   endmethod

   method Action putLine(Bit#(512) cacheline);
      in_line_fifo.enq(cacheline);
   endmethod

   method ActionValue#(Bit#(8)) getMatchMask();
      out_mask_fifo.deq();
      return out_mask_fifo.first();
   endmethod
endmodule

endpackage: StreamFilter
