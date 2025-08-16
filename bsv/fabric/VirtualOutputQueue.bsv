/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/fabric/VirtualOutputQueue.bsv
 * Description: Virtual Output Queue (VOQ) module buffering incoming memory
 *              requests across 4 target channels to prevent head-of-line blocking.
 *              Provides independent FIFO ports per channel for parallel access.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package VirtualOutputQueue;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;

interface VoqChannelPort;
   method Action enq(CxlMemM2SReq req);
   method Bool   notFull();
   method CxlMemM2SReq first();
   method Action deq();
   method Bool   notEmpty();
endinterface

interface Voq4Channel;
   interface Vector#(4, VoqChannelPort) channels;
   method Action enqToChannel(Bit#(2) dest_channel, CxlMemM2SReq req);
   method Bit#(4) notEmptyMask();
endinterface

(* synthesize *)
module mkVoq4Channel (Voq4Channel);
   Vector#(4, FIFOF#(CxlMemM2SReq)) queues <- replicateM(mkFIFOF());

   Vector#(4, VoqChannelPort) ports_vec = newVector();
   for (Integer i = 0; i < 4; i = i + 1) begin
      ports_vec[i] = interface VoqChannelPort;
         method Action enq(CxlMemM2SReq req);
            queues[i].enq(req);
         endmethod
         method Bool notFull();
            return queues[i].notFull();
         endmethod
         method CxlMemM2SReq first();
            return queues[i].first();
         endmethod
         method Action deq();
            queues[i].deq();
         endmethod
         method Bool notEmpty();
            return queues[i].notEmpty();
         endmethod
      endinterface;
   end

   interface channels = ports_vec;

   method Action enqToChannel(Bit#(2) dest_channel, CxlMemM2SReq req);
      queues[dest_channel].enq(req);
   endmethod

   method Bit#(4) notEmptyMask();
      Bit#(4) mask = 0;
      for (Integer i = 0; i < 4; i = i + 1) begin
         if (queues[i].notEmpty()) begin
            mask[i] = 1'b1;
         end
      end
      return mask;
   endmethod
endmodule

endpackage: VirtualOutputQueue
