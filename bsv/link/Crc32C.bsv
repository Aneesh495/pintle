/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/Crc32C.bsv
 * Description: High-throughput pipelined Castagnoli CRC-32C generator and validator
 *              for CXL 256-byte Standard Flits (Polynomial 0x1EDC6F41).
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Crc32C;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;

// Castagnoli Polynomial: 0x1EDC6F41 (reversed bit-order: 0x82F63B78)
Bit#(32) crc32c_POLY = 32'h82F63B78;

// Bit-by-bit step calculation for byte inputs
function Bit#(32) updateCrc32cByte(Bit#(32) current_crc, Bit#(8) data_byte);
   Bit#(32) c = current_crc ^ zeroExtend(data_byte);
   for (Integer i = 0; i < 8; i = i + 1) begin
      if (c[0] == 1'b1) begin
         c = (c >> 1) ^ crc32c_POLY;
      end else begin
         c = c >> 1;
      end
   end
   return c;
endfunction

// Step calculation for 128-bit flit slots (16 bytes per slot)
function Bit#(32) updateCrc32cSlot(Bit#(32) current_crc, Bit#(128) slot);
   Bit#(32) c = current_crc;
   for (Integer b = 0; b < 16; b = b + 1) begin
      Bit#(8) byte_val = slot[b*8 + 7 : b*8];
      c = updateCrc32cByte(c, byte_val);
   end
   return c;
endfunction

// Complete combinational calculation over standard 256-byte flit payload (14 slots + header)
function Bit#(32) computeFlitCrc(CxlStandardFlit flit);
   Bit#(32) c = 32'hFFFFFFFF;
   c = updateCrc32cByte(c, flit.flit_type);
   c = updateCrc32cByte(c, flit.seq_num);
   c = updateCrc32cByte(c, flit.ack_num);
   c = updateCrc32cByte(c, flit.credit_tokens);

   for (Integer s = 0; s < 14; s = s + 1) begin
      c = updateCrc32cSlot(c, flit.slots[s]);
   end

   return ~c; // Invert final output
endfunction

// ----------------------------------------------------------------------
// Hardware CRC Generator and Verifier Module Interface
// ----------------------------------------------------------------------

interface CrcEngine;
   method Action putFlit(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getFlitWithCrc();
   method ActionValue#(Bool) getVerificationResult();
endinterface

(* synthesize *)
module mkCrcEngine (CrcEngine);
   FIFOF#(CxlStandardFlit) in_fifo  <- mkFIFOF();
   FIFOF#(CxlStandardFlit) out_fifo <- mkFIFOF();
   FIFOF#(Bool)            vld_fifo <- mkFIFOF();

   rule process_flit;
      let flit = in_fifo.first();
      in_fifo.deq();

      Bit#(32) calculated_crc = computeFlitCrc(flit);
      Bool is_match = (calculated_crc == flit.crc);

      let tagged_flit = flit;
      tagged_flit.crc = calculated_crc;

      out_fifo.enq(tagged_flit);
      vld_fifo.enq(is_match);
   endrule

   method Action putFlit(CxlStandardFlit flit);
      in_fifo.enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getFlitWithCrc();
      out_fifo.deq();
      return out_fifo.first();
   endmethod

   method ActionValue#(Bool) getVerificationResult();
      vld_fifo.deq();
      return vld_fifo.first();
   endmethod
endmodule

endpackage: Crc32C
