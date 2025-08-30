/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/coherence/ConflictTable.bsv
 * Description: Miss Status Holding Register (MSHR) and address hazard conflict table,
 *              serializing concurrent multi-host accesses to identical cache lines.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package ConflictTable;

import Vector::*;
import CxlTypes::*;
import CoherenceTypes::*;

interface ConflictTable;
   method Bool hasConflict(Addr a);
   method Bool canAllocate();
   method ActionValue#(Maybe#(MshrIdx)) allocate(CxlMemM2SReq req, MshrPhase phase, CacheLineData data, SharerMask mask);
   method MshrEntry getEntry(MshrIdx idx);
   method Action updateEntry(MshrIdx idx, MshrEntry entry);
   method Action releaseEntry(MshrIdx idx);
   method UInt#(5) getActiveCount();
endinterface

(* synthesize *)
module mkConflictTable (ConflictTable);
   Vector#(16, Reg#(MshrEntry)) mshr_table <- replicateM(mkReg(unpack(0)));

   method Bool hasConflict(Addr a);
      Addr line_addr = lineAlignedAddress(a);
      Bool conflict = False;
      for (Integer i = 0; i < 16; i = i + 1) begin
         let entry = mshr_table[i];
         if (entry.valid && entry.addr == line_addr) begin
            conflict = True;
         end
      end
      return conflict;
   endmethod

   method Bool canAllocate();
      Bool free_slot_exists = False;
      for (Integer i = 0; i < 16; i = i + 1) begin
         if (!mshr_table[i].valid) begin
            free_slot_exists = True;
         end
      end
      return free_slot_exists;
   endmethod

   method ActionValue#(Maybe#(MshrIdx)) allocate(CxlMemM2SReq req, MshrPhase phase, CacheLineData data, SharerMask mask);
      Addr line_addr = lineAlignedAddress(req.addr);
      Maybe#(MshrIdx) free_idx = Invalid;

      for (Integer i = 0; i < 16; i = i + 1) begin
         if (!mshr_table[i].valid && free_idx == Invalid) begin
            free_idx = Valid(fromInteger(i));
         end
      end

      if (isValid(free_idx)) begin
         MshrIdx idx = fromMaybe(0, free_idx);
         MshrEntry new_entry = MshrEntry {
            valid:           True,
            addr:            line_addr,
            req_host:        req.host_id,
            req_tag:         req.tag,
            req_op:          req.opcode,
            phase:           phase,
            pending_bi_mask: mask,
            line_data:       data,
            dirty_writeback: False,
            byte_en:         req.byte_en
         };
         mshr_table[idx] <= new_entry;
      end

      return free_idx;
   endmethod

   method MshrEntry getEntry(MshrIdx idx);
      return mshr_table[idx];
   endmethod

   method Action updateEntry(MshrIdx idx, MshrEntry entry);
      mshr_table[idx] <= entry;
   endmethod

   method Action releaseEntry(MshrIdx idx);
      let e = mshr_table[idx];
      e.valid = False;
      mshr_table[idx] <= e;
   endmethod

   method UInt#(5) getActiveCount();
      UInt#(5) count = 0;
      for (Integer i = 0; i < 16; i = i + 1) begin
         if (mshr_table[i].valid) count = count + 1;
      end
      return count;
   endmethod
endmodule

endpackage: ConflictTable
