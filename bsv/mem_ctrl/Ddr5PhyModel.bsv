/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/Ddr5PhyModel.bsv
 * Description: Behavioral DDR5 SDRAM memory model with internal storage arrays,
 *              SECDED parity calculation, and programmable error injection.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Ddr5PhyModel;

import FIFOF::*;
import RegFile::*;
import CxlTypes::*;
import Ddr5Types::*;
import EccSecDed::*;

interface Ddr5PhyModel;
   method Action writeLine(Addr a, Bit#(512) data);
   method Action startRead(Bit#(12) req_id, Addr a);
   method ActionValue#(Tuple3#(Bit#(12), Bit#(512), Bit#(64))) getReadOutput();
   method Action injectError(Addr a, Bit#(2) num_bit_errors); // 1 = 1-bit, 2 = 2-bit
endinterface

(* synthesize *)
module mkDdr5PhyModel (Ddr5PhyModel);
   EccEngine ecc_engine <- mkEccEngine();

   RegFile#(Bit#(10), Bit#(512)) mem_data <- mkRegFileFull();
   RegFile#(Bit#(10), Bit#(64))  mem_ecc  <- mkRegFileFull();

   FIFOF#(Tuple3#(Bit#(12), Bit#(512), Bit#(64))) out_fifo <- mkFIFOF();

   function Bit#(10) getLineIdx(Addr a);
      return a[15:6];
   endfunction

   method Action writeLine(Addr a, Bit#(512) data);
      let idx = getLineIdx(a);
      Bit#(64) ecc = ecc_engine.encodeCacheLine(data);
      mem_data.upd(idx, data);
      mem_ecc.upd(idx, ecc);
   endmethod

   method Action startRead(Bit#(12) req_id, Addr a);
      let idx = getLineIdx(a);
      let d = mem_data.sub(idx);
      let e = mem_ecc.sub(idx);
      out_fifo.enq(tuple3(req_id, d, e));
   endmethod

   method ActionValue#(Tuple3#(Bit#(12), Bit#(512), Bit#(64))) getReadOutput();
      out_fifo.deq();
      return out_fifo.first();
   endmethod

   method Action injectError(Addr a, Bit#(2) num_bit_errors);
      let idx = getLineIdx(a);
      let d = mem_data.sub(idx);
      if (num_bit_errors == 1) begin
         // Flip bit 0
         mem_data.upd(idx, d ^ 512'h1);
      end else if (num_bit_errors == 2) begin
         // Flip bit 0 and bit 1
         mem_data.upd(idx, d ^ 512'h3);
      end
   endmethod
endmodule

endpackage: Ddr5PhyModel
