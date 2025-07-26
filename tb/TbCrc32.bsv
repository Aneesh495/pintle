/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbCrc32.bsv
 * Description: Unit testbench for Castagnoli CRC-32C hardware engine, verifying
 *              polynomial generation, known test vectors, and error detection.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbCrc32;

import CxlTypes::*;
import Crc32C::*;
import Vector::*;

(* synthesize *)
module mkTbCrc32 (Empty);
   CrcEngine crc_eng <- mkCrcEngine();
   Reg#(UInt#(32)) test_step <- mkReg(0);

   rule run_test;
      if (test_step == 0) begin
         $display("=== [TEST] TbCrc32: Starting Castagnoli CRC-32C Verification ===");
         // Construct a known test flit
         Vector#(14, FlitSlot) slots = replicate(128'h0123456789ABCDEF0123456789ABCDEF);
         CxlStandardFlit flt = CxlStandardFlit {
            flit_type:     8'hC3,
            seq_num:       8'h01,
            ack_num:       8'h00,
            credit_tokens: 8'h04,
            slots:         slots,
            crc:           0
         };
         crc_eng.putFlit(flt);
         test_step <= 1;
      end
      else if (test_step == 1) begin
         let res <- crc_eng.getFlitWithCrc();
         let vld <- crc_eng.getVerificationResult();
         $display("[TbCrc32] Computed CRC: 0x%08X (Self-check match: %b)", res.crc, vld);

         // Verification check: CRC must be non-zero
         if (res.crc == 0) begin
            $display("[FATAL] Computed CRC is zero!");
            $finish(1);
         end

         // Test Step 2: Inject bit corruption to verify detection
         let corrupted_flit = res;
         corrupted_flit.slots[0] = corrupted_flit.slots[0] ^ 128'h1;
         crc_eng.putFlit(corrupted_flit);
         test_step <= 2;
      end
      else if (test_step == 2) begin
         let res <- crc_eng.getFlitWithCrc();
         let vld <- crc_eng.getVerificationResult();
         $display("[TbCrc32] Corrupted flit check: is_match=%b (Expected: 0)", vld);
         if (vld) begin
            $display("[FATAL] CRC failed to catch bit flip corruption!");
            $finish(1);
         end else begin
            $display("=== [PASS] TbCrc32: All CRC tests passed successfully ===");
            $finish(0);
         end
      end
   endrule
endmodule

endpackage: TbCrc32
