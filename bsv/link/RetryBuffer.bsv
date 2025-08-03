/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/RetryBuffer.bsv
 * Description: Sliding-window link replay buffer for automatic link error recovery,
 *              supporting sequence-tracked retransmissions upon CRC failure.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package RetryBuffer;

import FIFOF::*;
import RegFile::*;
import CxlTypes::*;

typedef 64 RetryBufferSize;

interface RetryBuffer;
   method Action storeFlit(CxlStandardFlit flit);
   method Action acknowledgeUpTo(Bit#(8) ack_seq);
   method Action triggerReplay(Bit#(8) from_seq);
   method ActionValue#(CxlStandardFlit) getReplayFlit();
   method Bool isReplaying();
endinterface

(* synthesize *)
module mkRetryBuffer (RetryBuffer);
   RegFile#(Bit#(6), CxlStandardFlit) flit_storage <- mkRegFileFull();

   Reg#(Bit#(8)) head_seq   <- mkReg(0); // Oldest unacknowledged sequence
   Reg#(Bit#(8)) tail_seq   <- mkReg(0); // Next sequence to be written
   Reg#(Bit#(8)) replay_seq <- mkReg(0); // Current sequence being replayed
   Reg#(Bool)    replaying  <- mkReg(False);

   FIFOF#(CxlStandardFlit) replay_fifo <- mkFIFOF();

   rule do_replay if (replaying);
      if (replay_seq != tail_seq) begin
         Bit#(6) idx = truncate(replay_seq);
         let flt = flit_storage.sub(idx);
         replay_fifo.enq(flt);
         replay_seq <= replay_seq + 1;
      end else begin
         replaying <= False;
      end
   endrule

   method Action storeFlit(CxlStandardFlit flit);
      Bit#(6) idx = truncate(flit.seq_num);
      flit_storage.upd(idx, flit);
      tail_seq <= flit.seq_num + 1;
   endmethod

   method Action acknowledgeUpTo(Bit#(8) ack_seq);
      head_seq <= ack_seq;
   endmethod

   method Action triggerReplay(Bit#(8) from_seq);
      replay_seq <= from_seq;
      replaying  <= True;
   endmethod

   method ActionValue#(CxlStandardFlit) getReplayFlit();
      replay_fifo.deq();
      return replay_fifo.first();
   endmethod

   method Bool isReplaying();
      return replaying;
   endmethod
endmodule

endpackage: RetryBuffer
