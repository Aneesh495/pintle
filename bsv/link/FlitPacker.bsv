/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/FlitPacker.bsv
 * Description: Link layer 256-byte Flit packer, aggregating CXL.mem S2M responses,
 *              Back-Invalidation requests, and credit tokens into 256B flit frames.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package FlitPacker;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import Crc32C::*;

interface FlitPacker;
   method Action putMemRsp(CxlMemS2MRsp rsp);
   method Action returnCredits(Bit#(8) credits);
   method ActionValue#(CxlStandardFlit) getFlit();
endinterface

(* synthesize *)
module mkFlitPacker (FlitPacker);
   FIFOF#(CxlMemS2MRsp)     rsp_fifo       <- mkFIFOF();
   FIFOF#(Bit#(8))          credit_in_fifo <- mkFIFOF();
   FIFOF#(CxlStandardFlit)  out_flit_fifo  <- mkFIFOF();

   Reg#(Bit#(8)) seq_counter <- mkReg(0);
   Reg#(Bit#(8)) ack_counter <- mkReg(0);
   Reg#(Bit#(8)) pending_credits <- mkReg(0);

   rule accumulate_credits;
      let c = credit_in_fifo.first();
      credit_in_fifo.deq();
      pending_credits <= pending_credits + c;
   endrule

   rule pack_outbound_flit;
      let rsp = rsp_fifo.first();
      rsp_fifo.deq();

      // Determine credits to return in this flit
      Bit#(8) cred_to_send = (pending_credits > 15) ? 15 : pending_credits;
      pending_credits <= pending_credits - cred_to_send;

      // Format Slot 0: Header metadata
      Bit#(128) slot0 = 0;
      slot0[3:0]   = rsp.host_id;
      slot0[6:4]   = rsp.port_id;
      slot0[18:7]  = rsp.tag;
      slot0[21:19] = pack(rsp.status);
      slot0[22]    = rsp.has_data ? 1'b1 : 1'b0;

      // Format Slots 1..4: 512-bit cache line data (if present)
      Vector#(14, FlitSlot) slots = replicate(0);
      slots[0] = slot0;

      if (rsp.has_data) begin
         slots[1] = rsp.data[127:0];
         slots[2] = rsp.data[255:128];
         slots[3] = rsp.data[383:256];
         slots[4] = rsp.data[511:384];
      end

      CxlStandardFlit raw_flit = CxlStandardFlit {
         flit_type:     8'hC3, // CXL 3.0 Standard Memory Flit
         seq_num:       seq_counter,
         ack_num:       ack_counter,
         credit_tokens: cred_to_send,
         slots:         slots,
         crc:           0
      };

      // Compute and attach 32-bit CRC
      Bit#(32) calculated_crc = computeFlitCrc(raw_flit);
      raw_flit.crc = calculated_crc;

      out_flit_fifo.enq(raw_flit);
      seq_counter <= seq_counter + 1;
   endrule

   method Action putMemRsp(CxlMemS2MRsp rsp);
      rsp_fifo.enq(rsp);
   endmethod

   method Action returnCredits(Bit#(8) credits);
      credit_in_fifo.enq(credits);
   endmethod

   method ActionValue#(CxlStandardFlit) getFlit();
      out_flit_fifo.deq();
      return out_flit_fifo.first();
   endmethod
endmodule

endpackage: FlitPacker
