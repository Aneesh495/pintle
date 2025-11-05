/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/Ddr5Scheduler.bsv
 * Description: Multi-bank out-of-order DDR5 command scheduler prioritizing
 *              row buffer hits and enforcing strict JEDEC AC timing constraints.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Ddr5Scheduler;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import Ddr5Types::*;
import TimingEnforcer::*;
import BankQueue::*;
import EccSecDed::*;

interface Ddr5Scheduler;
   method Action putRequest(Ddr5MemRequest req);
   method ActionValue#(Ddr5MemResponse) getResponse();

   // Command interface to DDR5 PHY / SDRAM
   method ActionValue#(Tuple3#(Ddr5Cmd, GlobalBankIdx, RowAddr)) getIssuedCommand();
   method Action putPhyReadData(Bit#(12) req_id, Bit#(512) data, Bit#(64) ecc);
endinterface

(* synthesize *)
module mkDdr5Scheduler #(Ddr5TimingConfig timings) (Ddr5Scheduler);
   TimingEnforcer timing_ctrl <- mkTimingEnforcer(timings);
   EccEngine      ecc_engine  <- mkEccEngine();

   // 32 Bank Queues (4 bank groups * 8 banks)
   Vector#(32, BankQueue) bank_queues <- replicateM(mkBankQueue());

   FIFOF#(Ddr5MemResponse) rsp_out_fifo <- mkFIFOF();
   FIFOF#(Tuple3#(Ddr5Cmd, GlobalBankIdx, RowAddr)) cmd_out_fifo <- mkFIFOF();

   Reg#(GlobalBankIdx) rr_bank_ptr <- mkReg(0);

   // Rotating round-robin command scheduler across 32 banks
   rule schedule_banks;
      GlobalBankIdx b = rr_bank_ptr;
      Bool has_rd = bank_queues[b].hasPendingRead();
      Bool has_wr = bank_queues[b].hasPendingWrite();

      if (has_rd || has_wr) begin
         let req = has_rd ? bank_queues[b].peekRead() : bank_queues[b].peekWrite();
         let bstate = timing_ctrl.getBankState(b);
         let open_row = timing_ctrl.getActiveRow(b);

         if (bstate == BANK_ACTIVE && open_row == req.row) begin
            // Page Hit: issue read or write directly
            if (has_rd && timing_ctrl.canIssueRead(b, req.row)) begin
               timing_ctrl.recordRead(b);
               bank_queues[b].deqRead();
               cmd_out_fifo.enq(tuple3(DDR5_CMD_READ, b, req.row));
               rr_bank_ptr <= b + 1;
            end else if (has_wr && timing_ctrl.canIssueWrite(b, req.row)) begin
               timing_ctrl.recordWrite(b);
               bank_queues[b].deqWrite();
               cmd_out_fifo.enq(tuple3(DDR5_CMD_WRITE, b, req.row));
               Ddr5MemResponse wr_rsp = Ddr5MemResponse {
                  channel:         req.channel,
                  req_id:          req.req_id,
                  read_data:       0,
                  ecc_corrected:   False,
                  ecc_fatal_error: False
               };
               rsp_out_fifo.enq(wr_rsp);
               rr_bank_ptr <= b + 1;
            end
         end else if (bstate == BANK_ACTIVE && open_row != req.row) begin
            // Page Conflict: precharge active row
            if (timing_ctrl.canIssuePre(b)) begin
               timing_ctrl.recordPre(b);
               cmd_out_fifo.enq(tuple3(DDR5_CMD_PRE, b, open_row));
               rr_bank_ptr <= b + 1;
            end
         end else if (bstate == BANK_IDLE) begin
            // Page Empty: activate target row
            if (timing_ctrl.canIssueAct(b)) begin
               timing_ctrl.recordAct(b, req.row);
               cmd_out_fifo.enq(tuple3(DDR5_CMD_ACT, b, req.row));
               rr_bank_ptr <= b + 1;
            end
         end
      end else begin
         rr_bank_ptr <= b + 1;
      end
   endrule

   method Action putRequest(Ddr5MemRequest req);
      GlobalBankIdx b = toGlobalBank(req.bank_group, req.bank);
      bank_queues[b].enqRequest(req);
   endmethod

   method ActionValue#(Ddr5MemResponse) getResponse();
      rsp_out_fifo.deq();
      return rsp_out_fifo.first();
   endmethod

   method ActionValue#(Tuple3#(Ddr5Cmd, GlobalBankIdx, RowAddr)) getIssuedCommand();
      cmd_out_fifo.deq();
      return cmd_out_fifo.first();
   endmethod

   method Action putPhyReadData(Bit#(12) req_id, Bit#(512) data, Bit#(64) ecc);
      let dec = ecc_engine.decodeCacheLine(data, ecc);
      Bit#(512) corrected_data = tpl_1(dec);
      Bool had_1bit = tpl_2(dec);
      Bool had_fatal = tpl_3(dec);

      Ddr5MemResponse rsp = Ddr5MemResponse {
         channel:         0,
         req_id:          req_id,
         read_data:       corrected_data,
         ecc_corrected:   had_1bit,
         ecc_fatal_error: had_fatal
      };
      rsp_out_fifo.enq(rsp);
   endmethod
endmodule

endpackage: Ddr5Scheduler
