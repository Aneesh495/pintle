/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbBackInvalidator.bsv
 * Description: Unit testbench for BackInvalidator engine, verifying multi-host
 *              snoop broadcast, response aggregation, and dirty writeback capture.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbBackInvalidator;

import CxlTypes::*;
import CoherenceTypes::*;
import BackInvalidator::*;

(* synthesize *)
module mkTbBackInvalidator (Empty);
   BackInvalidator bi_eng <- mkBackInvalidator();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(UInt#(32)) cycle_cnt <- mkReg(0);
   Reg#(Bit#(8))   snoops_received <- mkReg(0);

   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 250) begin
         $display("[TIMEOUT] TbBackInvalidator exceeded max simulation cycles!");
         $finish(1);
      end
   endrule

   // Step 0: Trigger back-invalidation targeting Host 1 and Host 3
   rule drive_test if (test_step == 0);
      $display("=== [TEST] TbBackInvalidator: Starting Snoop Broadcast & Response Test ===");
      Addr test_addr = 64'hC0000000_56780000;
      SharerMask target = 8'b00001010; // Hosts 1 and 3
      bi_eng.startInvalidation(4'd2, test_addr, target, True);
      test_step <= 1;
   endrule

   // Step 1: Collect broadcast snoop requests
   rule collect_snoops if (test_step == 1);
      let snoop <- bi_eng.getSnoopReq();
      $display("[TbBackInvalidator] Captured snoop for host %0d, opcode=%0d",
               snoop.dest_host, pack(snoop.opcode));
      Bit#(8) updated = snoops_received | (8'b1 << snoop.dest_host);
      snoops_received <= updated;

      if (updated == 8'b00001010) begin
         $display("[TbBackInvalidator] All expected snoop broadcasts received.");
         test_step <= 2;
      end
   endrule

   // Step 2: Send response from Host 1 (clean)
   rule send_response1 if (test_step == 2);
      BackInvalidateRsp rsp1 = BackInvalidateRsp {
         src_host:       1,
         tag:            2,
         status:         BI_RSP_CLEAN,
         has_dirty_data: False,
         dirty_data:     0
      };
      bi_eng.putSnoopRsp(4'd2, rsp1);
      test_step <= 3;
   endrule

   // Step 3: Send response from Host 3 (dirty writeback)
   rule send_response3 if (test_step == 3);
      BackInvalidateRsp rsp3 = BackInvalidateRsp {
         src_host:       3,
         tag:            2,
         status:         BI_RSP_DIRTY,
         has_dirty_data: True,
         dirty_data:     512'hCAFEBABE_01234567_89ABCDEF_11223344_55667788_99AABBCC_DDEEFF00_A1B2C3D4
      };
      bi_eng.putSnoopRsp(4'd2, rsp3);
      test_step <= 4;
   endrule

   // Step 4: Verify completion firing and captured dirty writeback data
   rule verify_completion if (test_step == 4);
      let comp <- bi_eng.getCompletion();
      MshrIdx mshr_id = tpl_1(comp);
      Bool had_dirty = tpl_2(comp);
      CacheLineData d = tpl_3(comp);
      $display("[TbBackInvalidator] Completion: mshr_id=%0d, had_dirty=%b", mshr_id, had_dirty);

      if (mshr_id != 4'd2 || !had_dirty) begin
         $display("[FATAL] Completion mismatch or dirty writeback missed!");
         $finish(1);
      end else begin
         $display("=== [PASS] TbBackInvalidator: Multi-host invalidation verified ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbBackInvalidator
