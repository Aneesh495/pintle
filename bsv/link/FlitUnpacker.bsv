/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/FlitUnpacker.bsv
 * Description: Link layer 256-byte Flit unpacker, demultiplexing protocol slots
 *              into CXL.mem M2S requests, CXL.cache D2H requests, and link tokens.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package FlitUnpacker;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import Crc32C::*;

interface FlitUnpacker;
   method Action putFlit(CxlStandardFlit flit);
   method ActionValue#(CxlMemM2SReq) getMemReq();
   method ActionValue#(CacheLineData) getWriteData();
   method ActionValue#(Bit#(8)) getCreditReturn();
   method ActionValue#(Bool) getCrcErrorNotification();
endinterface

(* synthesize *)
module mkFlitUnpacker (FlitUnpacker);
   FIFOF#(CxlStandardFlit) in_fifo        <- mkFIFOF();
   FIFOF#(CxlMemM2SReq)    mem_req_fifo   <- mkFIFOF();
   FIFOF#(CacheLineData)   wr_data_fifo   <- mkFIFOF();
   FIFOF#(Bit#(8))         credit_fifo    <- mkFIFOF();
   FIFOF#(Bool)            crc_err_fifo   <- mkFIFOF();

   rule unpack_incoming_flit;
      let flit = in_fifo.first();
      in_fifo.deq();

      // Step 1: Verify CRC-32C checksum
      Bit#(32) expected_crc = computeFlitCrc(flit);
      Bool crc_ok = (expected_crc == flit.crc);

      if (!crc_ok) begin
         crc_err_fifo.enq(True);
      end else begin
         // Return credit tokens to flow control accumulator
         if (flit.credit_tokens > 0) begin
            credit_fifo.enq(flit.credit_tokens);
         end

         // Extract CXL.mem Request from Slot 0
         Bit#(128) slot0 = flit.slots[0];
         HostId   h_id   = slot0[3:0];
         PortId   p_id   = slot0[6:4];
         TagId    tag    = slot0[18:7];
         Bit#(3)  op_raw = slot0[21:19];
         Addr     addr   = slot0[85:22];
         ByteEn   be     = slot0[127:86] != 0 ? zeroExtend(slot0[127:86]) : ~64'b0;

         CxlMemOp op = unpack(zeroExtend(op_raw));

         CxlMemM2SReq req = CxlMemM2SReq {
            host_id:     h_id,
            port_id:     p_id,
            tag:         tag,
            opcode:      op,
            addr:        addr,
            byte_en:     be,
            is_prefetch: (slot0[22] == 1'b1)
         };

         mem_req_fifo.enq(req);

         // Extract 512-bit write data payload from Slots 1..4 if write request
         if (op == MEM_OP_WRITE || op == MEM_OP_WRITE_DATA) begin
            Bit#(512) payload = {flit.slots[4], flit.slots[3], flit.slots[2], flit.slots[1]};
            wr_data_fifo.enq(payload);
         end
      end
   endrule

   method Action putFlit(CxlStandardFlit flit);
      in_fifo.enq(flit);
   endmethod

   method ActionValue#(CxlMemM2SReq) getMemReq();
      mem_req_fifo.deq();
      return mem_req_fifo.first();
   endmethod

   method ActionValue#(CacheLineData) getWriteData();
      wr_data_fifo.deq();
      return wr_data_fifo.first();
   endmethod

   method ActionValue#(Bit#(8)) getCreditReturn();
      credit_fifo.deq();
      return credit_fifo.first();
   endmethod

   method ActionValue#(Bool) getCrcErrorNotification();
      crc_err_fifo.deq();
      return crc_err_fifo.first();
   endmethod
endmodule

endpackage: FlitUnpacker
