/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/FlitPacker.bsv
 * Description: Outbound CXL 256-byte Standard Flit assembler, packing CXL.mem
 *              requests/responses, returning credit tokens, and appending Castagnoli CRC-32C.
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
   method Action putMemReq(CxlMemM2SReq req, CacheLineData data);
   method Action returnCredits(Bit#(8) credits);
   method ActionValue#(CxlStandardFlit) getFlit();
endinterface

(* synthesize *)
module mkFlitPacker (FlitPacker);
   FIFOF#(CxlMemS2MRsp)                       rsp_fifo       <- mkFIFOF();
   FIFOF#(Tuple2#(CxlMemM2SReq, CacheLineData)) req_fifo     <- mkFIFOF();
   FIFOF#(Bit#(8))                            credit_in_fifo <- mkFIFOF();
   FIFOF#(CxlStandardFlit)                    out_flit_fifo  <- mkFIFOF();

   Reg#(Bit#(8)) seq_counter     <- mkReg(0);
   Reg#(Bit#(8)) ack_counter     <- mkReg(0);
   Reg#(Bit#(8)) pending_credits <- mkReg(0);

   rule accumulate_credits;
      let c = credit_in_fifo.first();
      credit_in_fifo.deq();
      pending_credits <= pending_credits + c;
   endrule

   rule pack_outbound_rsp if (rsp_fifo.notEmpty && !req_fifo.notEmpty);
      let rsp = rsp_fifo.first();
      rsp_fifo.deq();

      Bit#(8) cred_to_send = (pending_credits > 15) ? 15 : pending_credits;
      pending_credits <= pending_credits - cred_to_send;

      Bit#(128) slot0 = 0;
      slot0[3:0]   = rsp.host_id;
      slot0[6:4]   = rsp.port_id;
      slot0[18:7]  = rsp.tag;
      slot0[21:19] = pack(rsp.status);
      slot0[22]    = rsp.has_data ? 1'b1 : 1'b0;

      Vector#(14, FlitSlot) slots = replicate(0);
      slots[0] = slot0;

      if (rsp.has_data) begin
         slots[1] = rsp.data[127:0];
         slots[2] = rsp.data[255:128];
         slots[3] = rsp.data[383:256];
         slots[4] = rsp.data[511:384];
      end

      CxlStandardFlit raw_flit = CxlStandardFlit {
         flit_type:     8'hC3,
         seq_num:       seq_counter,
         ack_num:       ack_counter,
         credit_tokens: cred_to_send,
         slots:         slots,
         crc:           0
      };

      raw_flit.crc = computeFlitCrc(raw_flit);
      out_flit_fifo.enq(raw_flit);
      seq_counter <= seq_counter + 1;
   endrule

   rule pack_outbound_req if (req_fifo.notEmpty);
      let tuple_in = req_fifo.first();
      req_fifo.deq();
      let req  = tpl_1(tuple_in);
      let data = tpl_2(tuple_in);

      Bit#(8) cred_to_send = (pending_credits > 15) ? 15 : pending_credits;
      pending_credits <= pending_credits - cred_to_send;

      Bit#(128) slot0 = 0;
      slot0[3:0]   = req.host_id;
      slot0[6:4]   = req.port_id;
      slot0[18:7]  = req.tag;
      slot0[21:19] = pack(req.opcode);
      slot0[22]    = req.is_prefetch ? 1'b1 : 1'b0;
      slot0[85:23] = req.addr[62:0];

      Vector#(14, FlitSlot) slots = replicate(0);
      slots[0] = slot0;

      if (req.opcode == MEM_OP_WRITE || req.opcode == MEM_OP_WRITE_DATA) begin
         slots[1] = data[127:0];
         slots[2] = data[255:128];
         slots[3] = data[383:256];
         slots[4] = data[511:384];
      end

      CxlStandardFlit raw_flit = CxlStandardFlit {
         flit_type:     8'hC3,
         seq_num:       seq_counter,
         ack_num:       ack_counter,
         credit_tokens: cred_to_send,
         slots:         slots,
         crc:           0
      };

      raw_flit.crc = computeFlitCrc(raw_flit);
      out_flit_fifo.enq(raw_flit);
      seq_counter <= seq_counter + 1;
   endrule

   method Action putMemRsp(CxlMemS2MRsp rsp);
      rsp_fifo.enq(rsp);
   endmethod

   method Action putMemReq(CxlMemM2SReq req, CacheLineData data);
      req_fifo.enq(tuple2(req, data));
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
