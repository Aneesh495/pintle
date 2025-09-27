/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbEccSecDed.bsv
 * Description: Unit testbench for (72, 64) SECDED Hamming code engine, verifying
 *              error-free pass-through, single-bit correction, and double-bit detection.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbEccSecDed;

import CxlTypes::*;
import EccSecDed::*;

(* synthesize *)
module mkTbEccSecDed (Empty);
   EccEngine ecc <- mkEccEngine();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(Bit#(512)) orig_data <- mkReg(512'h12345678_9ABCDEF0_FEDCBA98_76543210_00112233_44556677_8899AABB_CCDDEEFF);
   Reg#(Bit#(64))  ecc_parity <- mkReg(0);

   rule step0 if (test_step == 0);
      $display("=== [TEST] TbEccSecDed: Starting SECDED Codec Verification ===");
      Bit#(64) parity = ecc.encodeCacheLine(orig_data);
      ecc_parity <= parity;
      $display("[TbEccSecDed] Generated ECC parity: 0x%016X", parity);

      // Phase 1: Verify clean data decodes with zero error flags
      let dec0 = ecc.decodeCacheLine(orig_data, parity);
      let d0 = tpl_1(dec0);
      let err1_0 = tpl_2(dec0);
      let fatal0 = tpl_3(dec0);
      $display("[TbEccSecDed] Clean decode: err1=%b, fatal=%b", err1_0, fatal0);

      if (d0 != orig_data || err1_0 || fatal0) begin
         $display("[FATAL] Clean data decode failed or raised false error flags!");
         $finish(1);
      end
      test_step <= 1;
   endrule

   rule step1 if (test_step == 1);
      // Phase 2: Inject single-bit error at bit 5
      Bit#(512) corrupted_1bit = orig_data ^ (512'h1 << 5);
      let dec1 = ecc.decodeCacheLine(corrupted_1bit, ecc_parity);
      let d1 = tpl_1(dec1);
      let err1_1 = tpl_2(dec1);
      let fatal1 = tpl_3(dec1);
      $display("[TbEccSecDed] Single-bit flip at bit 5: err1=%b, fatal=%b", err1_1, fatal1);

      if (!err1_1 || fatal1 || d1 != orig_data) begin
         $display("[FATAL] Single-bit correction failed to recover original data!");
         $finish(1);
      end
      test_step <= 2;
   endrule

   rule step2 if (test_step == 2);
      // Phase 3: Inject double-bit error at bits 5 and 6
      Bit#(512) corrupted_2bit = orig_data ^ (512'h1 << 5) ^ (512'h1 << 6);
      let dec2 = ecc.decodeCacheLine(corrupted_2bit, ecc_parity);
      let err1_2 = tpl_2(dec2);
      let fatal2 = tpl_3(dec2);
      $display("[TbEccSecDed] Double-bit flip at bits 5 and 6: err1=%b, fatal=%b", err1_2, fatal2);

      if (!fatal2) begin
         $display("[FATAL] Double-bit error was not caught by SECDED engine!");
         $finish(1);
      end else begin
         $display("=== [PASS] TbEccSecDed: All SECDED codec tests passed ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbEccSecDed
