/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/MemScrubber.bsv
 * Description: Autonomous background memory scrubber scanning idle rows, detecting
 *              single-bit soft errors, and rewriting SECDED-healed cache lines.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package MemScrubber;

import FIFOF::*;
import CxlTypes::*;
import EccSecDed::*;

interface MemScrubber;
   method Action setScrubEnable(Bool enable);
   method Action setScrubRate(UInt#(16) period_cycles);
   method ActionValue#(Addr) getScrubReadReq();
   method Action putScrubData(Addr a, Bit#(512) data, Bit#(64) ecc);
   method ActionValue#(Tuple2#(Addr, Bit#(512))) getScrubCorrectionWrite();
   method Bit#(32) getScrubbedCount();
   method Bit#(32) getCorrectedCount();
endinterface

(* synthesize *)
module mkMemScrubber (MemScrubber);
   EccEngine ecc_engine <- mkEccEngine();

   Reg#(Bool)     scrub_enabled <- mkReg(True);
   Reg#(UInt#(16)) scrub_period <- mkReg(100); // Check every 100 cycles
   Reg#(UInt#(16)) cycle_timer  <- mkReg(0);
   Reg#(Addr)     current_scrub_addr <- mkReg(0);

   Reg#(Bit#(32)) total_scrubbed  <- mkReg(0);
   Reg#(Bit#(32)) total_corrected <- mkReg(0);

   FIFOF#(Addr)                           scrub_req_fifo <- mkFIFOF();
   FIFOF#(Tuple2#(Addr, Bit#(512)))       scrub_wr_fifo  <- mkFIFOF();

   rule tick_scrubber if (scrub_enabled);
      if (cycle_timer >= scrub_period) begin
         cycle_timer <= 0;
         scrub_req_fifo.enq(current_scrub_addr);
         current_scrub_addr <= current_scrub_addr + 64; // Advance by 64B cache line
         total_scrubbed <= total_scrubbed + 1;
      end else begin
         cycle_timer <= cycle_timer + 1;
      end
   endrule

   method Action setScrubEnable(Bool enable);
      scrub_enabled <= enable;
   endmethod

   method Action setScrubRate(UInt#(16) period_cycles);
      scrub_period <= period_cycles;
   endmethod

   method ActionValue#(Addr) getScrubReadReq();
      scrub_req_fifo.deq();
      return scrub_req_fifo.first();
   endmethod

   method Action putScrubData(Addr a, Bit#(512) data, Bit#(64) ecc);
      let dec = ecc_engine.decodeCacheLine(data, ecc);
      Bit#(512) corrected = tpl_1(dec);
      Bool had_1bit = tpl_2(dec);

      if (had_1bit) begin
         total_corrected <= total_corrected + 1;
         scrub_wr_fifo.enq(tuple2(a, corrected));
      end
   endmethod

   method ActionValue#(Tuple2#(Addr, Bit#(512))) getScrubCorrectionWrite();
      scrub_wr_fifo.deq();
      return scrub_wr_fifo.first();
   endmethod

   method Bit#(32) getScrubbedCount();
      return total_scrubbed;
   endmethod

   method Bit#(32) getCorrectedCount();
      return total_corrected;
   endmethod
endmodule

endpackage: MemScrubber
