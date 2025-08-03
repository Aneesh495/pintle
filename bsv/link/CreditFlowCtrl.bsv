/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/link/CreditFlowCtrl.bsv
 * Description: Dual-ported credit-based link layer flow control engine,
 *              tracking transmitter credits and receiver buffer availability.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CreditFlowCtrl;

import FIFOF::*;

interface CreditFlowControl;
   method Action initCredits(Bit#(8) c);
   method Action consumeTxCredit();
   method Action addTxCredits(Bit#(8) credits);
   method Bool   hasTxCredit();
   method Action releaseRxBuffers(Bit#(8) count);
   method ActionValue#(Bit#(8)) getRxCreditsToReturn();
   method Bit#(8) getAvailableTxCredits();
endinterface

(* synthesize *)
module mkCreditFlowControl (CreditFlowControl);
   Reg#(Bit#(8)) tx_credits        <- mkReg(32); // Default initial credit pool
   Reg#(Bit#(8)) rx_buffered_freed <- mkReg(0);
   FIFOF#(Bit#(8)) credit_ret_fifo <- mkFIFOF();

   rule generate_credit_returns if (rx_buffered_freed > 0);
      Bit#(8) chunk = (rx_buffered_freed > 15) ? 15 : rx_buffered_freed;
      rx_buffered_freed <= rx_buffered_freed - chunk;
      credit_ret_fifo.enq(chunk);
   endrule

   method Action initCredits(Bit#(8) c);
      tx_credits <= c;
   endmethod

   method Action consumeTxCredit() if (tx_credits > 0);
      tx_credits <= tx_credits - 1;
   endmethod

   method Action addTxCredits(Bit#(8) credits);
      tx_credits <= tx_credits + credits;
   endmethod

   method Bool hasTxCredit();
      return (tx_credits > 0);
   endmethod

   method Action releaseRxBuffers(Bit#(8) count);
      rx_buffered_freed <= rx_buffered_freed + count;
   endmethod

   method ActionValue#(Bit#(8)) getRxCreditsToReturn();
      credit_ret_fifo.deq();
      return credit_ret_fifo.first();
   endmethod

   method Bit#(8) getAvailableTxCredits();
      return tx_credits;
   endmethod
endmodule

endpackage: CreditFlowCtrl
