/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/fabric/Arbiter.bsv
 * Description: High-performance arbitration primitives including fair Round-Robin,
 *              Deficit Round-Robin (DRR), and strict Priority arbiters.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Arbiter;

import Vector::*;

// ----------------------------------------------------------------------
// 4-Client Round-Robin Arbiter with Rotating Priority Wheel
// ----------------------------------------------------------------------

interface RoundRobinArbiter4;
   method Action request(Bit#(4) req_mask);
   method Maybe#(Bit#(2)) getGrant();
   method Action advanceGrant();
endinterface

(* synthesize *)
module mkRoundRobinArbiter4 (RoundRobinArbiter4);
   Reg#(Bit#(2)) last_granted <- mkReg(0);
   Reg#(Bit#(4)) current_reqs <- mkReg(0);

   function Maybe#(Bit#(2)) selectGrant(Bit#(4) reqs, Bit#(2) last_g);
      Maybe#(Bit#(2)) chosen = Invalid;

      // Scan starting from (last_g + 1) % 4
      for (Integer offset = 1; offset <= 4; offset = offset + 1) begin
         UInt#(3) last_val = zeroExtend(unpack(last_g));
         UInt#(3) cand_val = (last_val + fromInteger(offset)) % 4;
         Bit#(2) candidate = pack(truncate(cand_val));
         if (reqs[candidate] == 1'b1 && chosen == Invalid) begin
            chosen = Valid(candidate);
         end
      end
      return chosen;
   endfunction

   method Action request(Bit#(4) req_mask);
      current_reqs <= req_mask;
   endmethod

   method Maybe#(Bit#(2)) getGrant();
      return selectGrant(current_reqs, last_granted);
   endmethod

   method Action advanceGrant();
      let g = selectGrant(current_reqs, last_granted);
      if (isValid(g)) begin
         last_granted <= fromMaybe(0, g);
      end
   endmethod
endmodule

// ----------------------------------------------------------------------
// 4-Client Strict Priority Arbiter (Port 0 > Port 1 > Port 2 > Port 3)
// ----------------------------------------------------------------------

interface PriorityArbiter4;
   method Maybe#(Bit#(2)) selectPriority(Bit#(4) req_mask);
endinterface

(* synthesize *)
module mkPriorityArbiter4 (PriorityArbiter4);
   method Maybe#(Bit#(2)) selectPriority(Bit#(4) req_mask);
      if (req_mask[0] == 1'b1) return Valid(2'd0);
      else if (req_mask[1] == 1'b1) return Valid(2'd1);
      else if (req_mask[2] == 1'b1) return Valid(2'd2);
      else if (req_mask[3] == 1'b1) return Valid(2'd3);
      else return Invalid;
   endmethod
endmodule

endpackage: Arbiter
