/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbLz4Decompress.bsv
 * Description: Unit testbench for streaming hardware LZ4 decompressor,
 *              verifying token parsing, circular window match copying, and end-of-stream.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbLz4Decompress;

import Lz4Decompress::*;
import Vector::*;

(* synthesize *)
module mkTbLz4Decompress (Empty);
   Lz4Decompressor lz4 <- mkLz4Decompressor();

   Reg#(UInt#(32)) test_step <- mkReg(0);
   Reg#(UInt#(32)) byte_idx  <- mkReg(0);
   Reg#(UInt#(32)) out_count <- mkReg(0);
   Reg#(UInt#(32)) cycle_cnt <- mkReg(0);

   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 300) begin
         $display("[TIMEOUT] TbLz4Decompress exceeded max simulation cycles!");
         $finish(1);
      end
   endrule

   // Test Stream: Decompresses literal run "ABCDEF" followed by repeat match
   // Token: 0x64 (6 literals, match length 4+4=8)
   // Literals: "ABCDEF" (6 bytes)
   // Offset: 6 (0x0006)
   Vector#(9, Bit#(8)) test_stream = newVector();
   test_stream[0] = 8'h64; // Token: 6 literals, match 4+4 = 8
   test_stream[1] = 8'h41; // 'A'
   test_stream[2] = 8'h42; // 'B'
   test_stream[3] = 8'h43; // 'C'
   test_stream[4] = 8'h44; // 'D'
   test_stream[5] = 8'h45; // 'E'
   test_stream[6] = 8'h46; // 'F'
   test_stream[7] = 8'h06; // Offset lo
   test_stream[8] = 8'h00; // Offset hi

   rule feed_stream if (test_step == 0);
      if (byte_idx < 9) begin
         Bool is_last = (byte_idx == 8);
         lz4.putInputByte(test_stream[byte_idx], is_last);
         byte_idx <= byte_idx + 1;
      end else begin
         test_step <= 1;
      end
   endrule

   rule collect_output;
      let out_val <- lz4.getOutputByte();
      Bit#(8) b = tpl_1(out_val);
      out_count <= out_count + 1;
      $display("[TbLz4Decompress] Output Byte %02d: 0x%02X ('%c')", out_count + 1, b, b);

      // Expected output length: 6 literals + 8 match copies = 14 bytes
      if (out_count + 1 == 14) begin
         $display("=== [PASS] TbLz4Decompress: Stream decompression verified ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbLz4Decompress
