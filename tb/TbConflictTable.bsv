/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbConflictTable.bsv
 * Description: Unit testbench for MSHR ConflictTable, verifying address hazard
 *              detection, serialization, and slot recycling across clock cycles.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbConflictTable;

import CxlTypes::*;
import CoherenceTypes::*;
import ConflictTable::*;

(* synthesize *)
module mkTbConflictTable (Empty);
   ConflictTable ct <- mkConflictTable();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(MshrIdx)   allocated_slot <- mkReg(0);

   rule step0 if (test_step == 0);
      $display("=== [TEST] TbConflictTable: Starting Hazard Table Verification ===");
      Addr test_line = 64'hF0000000_12340000;
      Bool conflict = ct.hasConflict(test_line);
      $display("[TbConflictTable] Initial conflict check: %b (Expected: 0)", conflict);
      if (conflict) begin
         $display("[FATAL] Conflict reported on empty table!");
         $finish(1);
      end

      // Allocate MSHR slot for test_line
      CxlMemM2SReq req0 = CxlMemM2SReq {
         host_id: 0, port_id: 0, tag: 12'h001, opcode: MEM_OP_READ,
         addr: test_line, byte_en: ~64'b0, is_prefetch: False
      };
      let maybe_mshr <- ct.allocate(req0, MSHR_DIR_LOOKUP, 0, 0);
      if (!isValid(maybe_mshr)) begin
         $display("[FATAL] Failed to allocate MSHR slot!");
         $finish(1);
      end
      allocated_slot <= fromMaybe(0, maybe_mshr);
      test_step <= 1;
   endrule

   rule step1 if (test_step == 1);
      // Check conflict on identical address and same cache line with different offset
      Addr same_line_diff_offset = 64'hF0000000_12340028; // byte offset 0x28 (within same 64B line)
      Bool conflict = ct.hasConflict(same_line_diff_offset);
      $display("[TbConflictTable] Hazard check on same cache line (offset 0x28): %b (Expected: 1)", conflict);
      if (!conflict) begin
         $display("[FATAL] Conflict table missed intra-cacheline address hazard!");
         $finish(1);
      end
      test_step <= 2;
   endrule

   rule step2 if (test_step == 2);
      // Check conflict on different cache line
      Addr diff_line = 64'hF0000000_12340040; // next 64B cache line
      Bool diff_conflict = ct.hasConflict(diff_line);
      $display("[TbConflictTable] Check on distinct line: %b (Expected: 0)", diff_conflict);
      if (diff_conflict) begin
         $display("[FATAL] False conflict detected on distinct line!");
         $finish(1);
      end

      // Release entry and verify conflict clears
      ct.releaseEntry(allocated_slot);
      test_step <= 3;
   endrule

   rule step3 if (test_step == 3);
      Addr test_line = 64'hF0000000_12340000;
      Bool conflict = ct.hasConflict(test_line);
      $display("[TbConflictTable] Post-release conflict check: %b (Expected: 0)", conflict);
      if (conflict) begin
         $display("[FATAL] Entry release failed, conflict still asserted!");
         $finish(1);
      end else begin
         $display("=== [PASS] TbConflictTable: All hazard serialization tests passed ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbConflictTable
