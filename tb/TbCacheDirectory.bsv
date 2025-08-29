/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbCacheDirectory.bsv
 * Description: Unit testbench for set-associative CacheDirectory, verifying
 *              tag matching, MOESI state transitions, and sharer tracking.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbCacheDirectory;

import CxlTypes::*;
import CoherenceTypes::*;
import CacheDirectory::*;

(* synthesize *)
module mkTbCacheDirectory (Empty);
   CacheDirectory dir <- mkCacheDirectory();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(UInt#(32)) cycle_cnt <- mkReg(0);

   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 200) begin
         $display("[TIMEOUT] TbCacheDirectory exceeded max cycles!");
         $finish(1);
      end
   endrule

   rule run_tests;
      if (test_step == 0) begin
         $display("=== [TEST] TbCacheDirectory: Starting Directory Cache Verification ===");
         Addr test_addr = 64'hA0000000_12340040;
         let res = dir.lookup(test_addr);
         Bool hit = tpl_1(res);
         $display("[TbCacheDirectory] Initial lookup for unallocated line: hit=%b (Expected: 0)", hit);
         if (hit) begin
            $display("[FATAL] Unallocated line returned directory hit!");
            $finish(1);
         end

         // Step 1: Install line in Shared state with Host 0 and Host 1 as sharers
         DirectoryEntry entry0 = DirectoryEntry {
            valid:          True,
            tag:            test_addr[63:32],
            state:          COH_SHARED,
            sharers:        8'b00000011, // Host 0 and 1
            owner:          0,
            is_device_bias: False
         };
         dir.update(test_addr, entry0);
         test_step <= 1;
      end
      else if (test_step == 1) begin
         Addr test_addr = 64'hA0000000_12340040;
         let res = dir.lookup(test_addr);
         Bool hit = tpl_1(res);
         DirectoryEntry entry = tpl_2(res);
         $display("[TbCacheDirectory] Post-update lookup: hit=%b, state=%0d, sharers=0x%02X",
                  hit, pack(entry.state), entry.sharers);

         if (!hit || entry.state != COH_SHARED || entry.sharers != 8'b00000011) begin
            $display("[FATAL] Directory entry corrupted or mismatch!");
            $finish(1);
         end

         // Step 2: Transition to Modified state with Host 2 as owner
         DirectoryEntry entry_mod = DirectoryEntry {
            valid:          True,
            tag:            test_addr[63:32],
            state:          COH_MODIFIED,
            sharers:        8'b00000100, // Host 2
            owner:          2,
            is_device_bias: False
         };
         dir.update(test_addr, entry_mod);
         test_step <= 2;
      end
      else if (test_step == 2) begin
         Addr test_addr = 64'hA0000000_12340040;
         let res = dir.lookup(test_addr);
         DirectoryEntry entry = tpl_2(res);
         $display("[TbCacheDirectory] Modified state verify: state=%0d, owner=%0d",
                  pack(entry.state), entry.owner);

         if (entry.state != COH_MODIFIED || entry.owner != 2) begin
            $display("[FATAL] Expected Modified state with owner 2!");
            $finish(1);
         end

         // Step 3: Invalidate line
         dir.invalidateLine(test_addr);
         test_step <= 3;
      end
      else if (test_step == 3) begin
         Addr test_addr = 64'hA0000000_12340040;
         let res = dir.lookup(test_addr);
         Bool hit = tpl_1(res);
         $display("[TbCacheDirectory] Post-invalidation lookup: hit=%b (Expected: 0)", hit);
         if (hit) begin
            $display("[FATAL] Invalidation failed, line still reports hit!");
            $finish(1);
         end else begin
            $display("=== [PASS] TbCacheDirectory: All directory tests passed ===");
            $finish(0);
         end
      end
   endrule
endmodule

endpackage: TbCacheDirectory
