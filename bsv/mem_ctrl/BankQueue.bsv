/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/BankQueue.bsv
 * Description: Per-bank request queues prioritizing row buffer page hits,
 *              supporting read-over-write scheduling and write-drain thresholds.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package BankQueue;

import FIFOF::*;
import Vector::*;
import Ddr5Types::*;

interface BankQueue;
   method Action enqRequest(Ddr5MemRequest req);
   method Bool   hasPendingRead();
   method Bool   hasPendingWrite();
   method Ddr5MemRequest peekRead();
   method Ddr5MemRequest peekWrite();
   method Action deqRead();
   method Action deqWrite();
   method UInt#(5) getReadCount();
   method UInt#(5) getWriteCount();
endinterface

(* synthesize *)
module mkBankQueue (BankQueue);
   FIFOF#(Ddr5MemRequest) rd_queue <- mkFIFOF();
   FIFOF#(Ddr5MemRequest) wr_queue <- mkFIFOF();

   Reg#(UInt#(5)) rd_count <- mkReg(0);
   Reg#(UInt#(5)) wr_count <- mkReg(0);

   method Action enqRequest(Ddr5MemRequest req);
      if (req.is_write) begin
         wr_queue.enq(req);
         wr_count <= wr_count + 1;
      end else begin
         rd_queue.enq(req);
         rd_count <= rd_count + 1;
      end
   endmethod

   method Bool hasPendingRead();
      return rd_queue.notEmpty();
   endmethod

   method Bool hasPendingWrite();
      return wr_queue.notEmpty();
   endmethod

   method Ddr5MemRequest peekRead();
      return rd_queue.first();
   endmethod

   method Ddr5MemRequest peekWrite();
      return wr_queue.first();
   endmethod

   method Action deqRead();
      rd_queue.deq();
      if (rd_count > 0) rd_count <= rd_count - 1;
   endmethod

   method Action deqWrite();
      wr_queue.deq();
      if (wr_count > 0) wr_count <= wr_count - 1;
   endmethod

   method UInt#(5) getReadCount();
      return rd_count;
   endmethod

   method UInt#(5) getWriteCount();
      return wr_count;
   endmethod
endmodule

endpackage: BankQueue
