/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/accel/Lz4Decompress.bsv
 * Description: Streaming line-rate LZ4 hardware decompression pipeline with
 *              circular history match buffer and AXI-Stream output.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Lz4Decompress;

import FIFOF::*;
import Vector::*;
import RegFile::*;
import AxiTypes::*;

typedef enum {
   LZ4_IDLE,
   LZ4_READ_TOKEN,
   LZ4_READ_LIT_EXTRA,
   LZ4_COPY_LITERALS,
   LZ4_READ_OFFSET_LO,
   LZ4_READ_OFFSET_HI,
   LZ4_READ_MATCH_EXTRA,
   LZ4_COPY_MATCH,
   LZ4_DONE
} Lz4State deriving (Bits, Eq, FShow);

interface Lz4Decompressor;
   method Action putInputByte(Bit#(8) b, Bool is_last);
   method ActionValue#(Tuple2#(Bit#(8), Bool)) getOutputByte();
   method Bool isBusy();
endinterface

(* synthesize *)
module mkLz4Decompressor (Lz4Decompressor);
   FIFOF#(Tuple2#(Bit#(8), Bool)) in_fifo  <- mkFIFOF();
   FIFOF#(Tuple2#(Bit#(8), Bool)) out_fifo <- mkFIFOF();

   Reg#(Lz4State) state <- mkReg(LZ4_IDLE);

   // Circular history window buffer (4KB for compact hardware model)
   RegFile#(Bit#(12), Bit#(8)) history_buffer <- mkRegFileFull();
   Reg#(Bit#(12)) write_ptr <- mkReg(0);

   // Parsing state variables
   Reg#(UInt#(16)) lit_len   <- mkReg(0);
   Reg#(UInt#(16)) match_len <- mkReg(0);
   Reg#(Bit#(16))  offset    <- mkReg(0);
   Reg#(Bit#(8))   offset_lo <- mkReg(0);
   Reg#(Bit#(12))  match_src <- mkReg(0);

   rule decompress_step;
      case (state)
         LZ4_IDLE: begin
            if (in_fifo.notEmpty()) begin
               state <= LZ4_READ_TOKEN;
            end
         end

         LZ4_READ_TOKEN: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            Bit#(8) token = tpl_1(in_val);

            UInt#(16) raw_lit = zeroExtend(unpack(token[7:4]));
            UInt#(16) raw_mat = zeroExtend(unpack(token[3:0])) + 4; // Min match is 4

            lit_len   <= raw_lit;
            match_len <= raw_mat;

            if (raw_lit == 15) begin
               state <= LZ4_READ_LIT_EXTRA;
            end else if (raw_lit > 0) begin
               state <= LZ4_COPY_LITERALS;
            end else begin
               state <= LZ4_READ_OFFSET_LO;
            end
         end

         LZ4_READ_LIT_EXTRA: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            Bit#(8) extra = tpl_1(in_val);
            UInt#(16) new_len = lit_len + zeroExtend(unpack(extra));
            lit_len <= new_len;

            if (extra != 8'hFF) begin
               state <= LZ4_COPY_LITERALS;
            end
         end

         LZ4_COPY_LITERALS: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            Bit#(8) lit_byte = tpl_1(in_val);
            Bool is_last = tpl_2(in_val);

            // Emit to output stream and record in history buffer
            out_fifo.enq(tuple2(lit_byte, False));
            history_buffer.upd(write_ptr, lit_byte);
            write_ptr <= write_ptr + 1;

            if (lit_len == 1) begin
               if (is_last) begin
                  state <= LZ4_DONE;
               end else begin
                  state <= LZ4_READ_OFFSET_LO;
               end
            end else begin
               lit_len <= lit_len - 1;
            end
         end

         LZ4_READ_OFFSET_LO: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            offset_lo <= tpl_1(in_val);
            state <= LZ4_READ_OFFSET_HI;
         end

         LZ4_READ_OFFSET_HI: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            Bit#(8) offset_hi = tpl_1(in_val);
            Bit#(16) full_offset = {offset_hi, offset_lo};
            offset <= full_offset;

            // Calculate starting read pointer in circular history buffer
            Bit#(12) src = write_ptr - truncate(full_offset);
            match_src <= src;

            if (match_len == 19) begin // 15 + 4
               state <= LZ4_READ_MATCH_EXTRA;
            end else begin
               state <= LZ4_COPY_MATCH;
            end
         end

         LZ4_READ_MATCH_EXTRA: begin
            let in_val = in_fifo.first();
            in_fifo.deq();
            Bit#(8) extra = tpl_1(in_val);
            UInt#(16) new_len = match_len + zeroExtend(unpack(extra));
            match_len <= new_len;

            if (extra != 8'hFF) begin
               state <= LZ4_COPY_MATCH;
            end
         end

         LZ4_COPY_MATCH: begin
            Bit#(8) match_byte = history_buffer.sub(match_src);
            out_fifo.enq(tuple2(match_byte, False));
            history_buffer.upd(write_ptr, match_byte);

            write_ptr <= write_ptr + 1;
            match_src <= match_src + 1;

            if (match_len == 1) begin
               if (in_fifo.notEmpty()) begin
                  state <= LZ4_READ_TOKEN;
               end else begin
                  state <= LZ4_DONE;
               end
            end else begin
               match_len <= match_len - 1;
            end
         end

         LZ4_DONE: begin
            state <= LZ4_IDLE;
         end
      endcase
   endrule

   method Action putInputByte(Bit#(8) b, Bool is_last);
      in_fifo.enq(tuple2(b, is_last));
   endmethod

   method ActionValue#(Tuple2#(Bit#(8), Bool)) getOutputByte();
      out_fifo.deq();
      return out_fifo.first();
   endmethod

   method Bool isBusy();
      return (state != LZ4_IDLE);
   endmethod
endmodule

endpackage: Lz4Decompress
