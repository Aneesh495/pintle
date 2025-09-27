/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/EccSecDed.bsv
 * Description: (72, 64) Single-Error-Correction Double-Error-Detection (SECDED)
 *              Hamming code engine protecting 512-bit cache lines against soft errors.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package EccSecDed;

import Vector::*;
import CxlTypes::*;

// ----------------------------------------------------------------------
// 64-Bit Data to 8-Bit SECDED Parity Codec Functions
// ----------------------------------------------------------------------

function Bit#(8) computeParity64(Bit#(64) d);
   Bit#(8) p = 0;

   // Parity bit 0: covers bits with bit 0 set in position index (1, 3, 5, 7, ...)
   Bit#(1) p0 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if ((i % 2) == 1) p0 = p0 ^ d[i];
   end
   p[0] = p0;

   // Parity bit 1: covers bits with bit 1 set (2, 3, 6, 7, ...)
   Bit#(1) p1 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if (((i / 2) % 2) == 1) p1 = p1 ^ d[i];
   end
   p[1] = p1;

   // Parity bit 2: covers bits with bit 2 set (4..7, 12..15, ...)
   Bit#(1) p2 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if (((i / 4) % 2) == 1) p2 = p2 ^ d[i];
   end
   p[2] = p2;

   // Parity bit 3: covers bits with bit 3 set (8..15, 24..31, ...)
   Bit#(1) p3 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if (((i / 8) % 2) == 1) p3 = p3 ^ d[i];
   end
   p[3] = p3;

   // Parity bit 4: covers bits with bit 4 set (16..31, 48..63)
   Bit#(1) p4 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if (((i / 16) % 2) == 1) p4 = p4 ^ d[i];
   end
   p[4] = p4;

   // Parity bit 5: covers bits with bit 5 set (32..63)
   Bit#(1) p5 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      if (((i / 32) % 2) == 1) p5 = p5 ^ d[i];
   end
   p[5] = p5;

   // Parity bit 6: parity over odd half
   Bit#(1) p6 = 0;
   for (Integer i = 0; i < 32; i = i + 1) begin
      p6 = p6 ^ d[i * 2];
   end
   p[6] = p6;

   // Parity bit 7: overall data parity for double-error detection
   Bit#(1) p7 = 0;
   for (Integer i = 0; i < 64; i = i + 1) begin
      p7 = p7 ^ d[i];
   end
   p[7] = p7;

   return p;
endfunction

function Tuple3#(Bit#(64), Bool, Bool) decodeSecDed64(Bit#(64) raw_data, Bit#(8) raw_p);
   Bit#(8) expected_p = computeParity64(raw_data);
   Bit#(8) syndrome   = expected_p ^ raw_p;

   Bool overall_parity_err = (syndrome[7] == 1'b1);
   Bit#(7) pos_syndrome    = syndrome[6:0];

   if (syndrome == 0) begin
      // Zero errors detected
      return tuple3(raw_data, False, False);
   end else if (overall_parity_err) begin
      // Single-bit error detected: correct the bit
      Bit#(6) bit_idx = truncate(pos_syndrome[5:0]);
      Bit#(64) corrected = raw_data ^ (64'b1 << bit_idx);
      return tuple3(corrected, True, False);
   end else begin
      // Double-bit uncorrectable error detected
      return tuple3(raw_data, False, True);
   end
endfunction

// ----------------------------------------------------------------------
// 512-Bit Cache Line SECDED Codec Interface
// ----------------------------------------------------------------------

interface EccEngine;
   method Bit#(64) encodeCacheLine(Bit#(512) data);
   method Tuple3#(Bit#(512), Bool, Bool) decodeCacheLine(Bit#(512) data, Bit#(64) ecc);
endinterface

(* synthesize *)
module mkEccEngine (EccEngine);
   method Bit#(64) encodeCacheLine(Bit#(512) data);
      Bit#(64) full_ecc = 0;
      for (Integer w = 0; w < 8; w = w + 1) begin
         Bit#(64) word = data[w * 64 + 63 : w * 64];
         Bit#(8) p = computeParity64(word);
         full_ecc[w * 8 + 7 : w * 8] = p;
      end
      return full_ecc;
   endmethod

   method Tuple3#(Bit#(512), Bool, Bool) decodeCacheLine(Bit#(512) data, Bit#(64) ecc);
      Bit#(512) corrected_line = 0;
      Bool had_1bit_err = False;
      Bool had_fatal_err = False;

      for (Integer w = 0; w < 8; w = w + 1) begin
         Bit#(64) word = data[w * 64 + 63 : w * 64];
         Bit#(8)  p    = ecc[w * 8 + 7 : w * 8];
         let dec = decodeSecDed64(word, p);
         corrected_line[w * 64 + 63 : w * 64] = tpl_1(dec);
         if (tpl_2(dec)) had_1bit_err  = True;
         if (tpl_3(dec)) had_fatal_err = True;
      end

      return tuple3(corrected_line, had_1bit_err, had_fatal_err);
   endmethod
endmodule

endpackage: EccSecDed
