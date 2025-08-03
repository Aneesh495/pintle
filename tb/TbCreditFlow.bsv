/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbCreditFlow.bsv
 * Description: Unit testbench for CXL credit flow control engine, verifying
 *              credit consumption, backpressure stall, and token replenishment.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbCreditFlow;

import CreditFlowCtrl::*;

(* synthesize *)
module mkTbCreditFlow (Empty);
   CreditFlowControl flow_ctrl <- mkCreditFlowControl();

   Reg#(UInt#(32)) step  <- mkReg(0);
   Reg#(Bit#(8))   count <- mkReg(0);

   rule run_credit_test;
      if (step == 0) begin
         $display("=== [TEST] TbCreditFlow: Starting Credit Flow Control Verification ===");
         flow_ctrl.initCredits(8'd4); // Initialize with 4 credits
         step <= 1;
      end
      else if (step == 1) begin
         // Consume all 4 credits
         if (flow_ctrl.hasTxCredit()) begin
            flow_ctrl.consumeTxCredit();
            count <= count + 1;
            $display("[TbCreditFlow] Consumed credit, total consumed=%0d", count + 1);
         end else begin
            $display("[TbCreditFlow] Credits depleted as expected. Available: %0d",
                     flow_ctrl.getAvailableTxCredits());
            if (count != 8'd4) begin
               $display("[FATAL] Expected 4 credits consumed before stall, got %0d", count);
               $finish(1);
            end
            step <= 2;
         end
      end
      else if (step == 2) begin
         $display("[TbCreditFlow] Adding 8 credits from peer flit...");
         flow_ctrl.addTxCredits(8'd8);
         step <= 3;
      end
      else if (step == 3) begin
         Bit#(8) avail = flow_ctrl.getAvailableTxCredits();
         $display("[TbCreditFlow] Current available TX credits: %0d (Expected: 8)", avail);
         if (avail != 8'd8) begin
            $display("[FATAL] Expected 8 available credits, got %0d", avail);
            $finish(1);
         end

         // Test receiver buffer release
         flow_ctrl.releaseRxBuffers(8'd2);
         step <= 4;
      end
      else if (step == 4) begin
         let ret <- flow_ctrl.getRxCreditsToReturn();
         $display("[TbCreditFlow] Generated credit return token: %0d (Expected: 2)", ret);
         if (ret != 8'd2) begin
            $display("[FATAL] Expected 2 returned credits, got %0d", ret);
            $finish(1);
         end else begin
            $display("=== [PASS] TbCreditFlow: All credit flow tests passed ===");
            $finish(0);
         end
      end
   endrule
endmodule

endpackage: TbCreditFlow
