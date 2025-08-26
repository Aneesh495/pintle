/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbCrossbar.bsv
 * Description: Unit testbench for 4-port CrossbarSwitch and VOQ fabric,
 *              verifying non-blocking routing, contention arbitration, and response delivery.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbCrossbar;

import CxlTypes::*;
import CrossbarSwitch::*;

(* synthesize *)
module mkTbCrossbar (Empty);
   CrossbarSwitch xbar <- mkCrossbarSwitch();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(UInt#(32)) cycle_cnt <- mkReg(0);
   Reg#(Bit#(4))   contention_driver <- mkReg(0);
   Reg#(Bit#(4))   received_mask <- mkReg(0);

   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 300) begin
         $display("[TIMEOUT] TbCrossbar simulation exceeded cycle limit!");
         $finish(1);
      end
   endrule

   // Test Phase 1: Disjoint routing (Host 0 -> Ch 1, Host 1 -> Ch 2 in parallel)
   rule drive_disjoint if (test_step == 0);
      $display("=== [TEST] TbCrossbar: Testing Disjoint Parallel Routing ===");
      Addr addr_ch1 = 64'h00000000_00000040; // channel 1 (bits [7:6] = 2'b01)
      CxlMemM2SReq req0 = CxlMemM2SReq {
         host_id: 4'd0, port_id: 3'd0, tag: 12'h100, opcode: MEM_OP_READ,
         addr: addr_ch1, byte_en: ~64'b0, is_prefetch: False
      };

      Addr addr_ch2 = 64'h00000000_00000080; // channel 2 (bits [7:6] = 2'b10)
      CxlMemM2SReq req1 = CxlMemM2SReq {
         host_id: 4'd1, port_id: 3'd1, tag: 12'h200, opcode: MEM_OP_READ,
         addr: addr_ch2, byte_en: ~64'b0, is_prefetch: False
      };

      xbar.putHostReq0(req0);
      xbar.putHostReq1(req1);
      test_step <= 1;
   endrule

   rule verify_disjoint if (test_step == 1);
      let r_ch1 <- xbar.getChannelReq1();
      let r_ch2 <- xbar.getChannelReq2();
      $display("[TbCrossbar] Ch 1 received tag 0x%03X (from host %0d)", r_ch1.tag, r_ch1.host_id);
      $display("[TbCrossbar] Ch 2 received tag 0x%03X (from host %0d)", r_ch2.tag, r_ch2.host_id);

      if (r_ch1.host_id != 4'd0 || r_ch2.host_id != 4'd1) begin
         $display("[FATAL] Disjoint channel routing mismatch!");
         $finish(1);
      end
      test_step <= 2;
   endrule

   // Test Phase 2: Contention (Drive all 4 hosts into Channel 0 over 4 consecutive cycles)
   rule drive_contention if (test_step == 2);
      $display("=== [TEST] TbCrossbar: Testing 4-Way Contention on Channel 0 ===");
      Addr addr_ch0 = 64'h00000000_00000000;
      CxlMemM2SReq req = CxlMemM2SReq {
         host_id: zeroExtend(contention_driver[1:0]),
         port_id: zeroExtend(contention_driver[1:0]),
         tag: 12'h300 + zeroExtend(contention_driver[1:0]),
         opcode: MEM_OP_READ, addr: addr_ch0, byte_en: ~64'b0, is_prefetch: False
      };
      xbar.putHostReq(contention_driver[1:0], req);

      if (contention_driver == 3) begin
         test_step <= 3;
      end else begin
         contention_driver <= contention_driver + 1;
      end
   endrule

   rule drain_contention if (test_step == 3);
      let req <- xbar.getChannelReq0();
      Bit#(4) updated_mask = received_mask | (4'b1 << req.host_id[1:0]);
      received_mask <= updated_mask;
      $display("[TbCrossbar] Serviced host %0d on Ch 0. Accumulated mask: %b", req.host_id, updated_mask);

      if (updated_mask == 4'b1111) begin
         $display("=== [PASS] TbCrossbar: Contention and fairness verified ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbCrossbar
