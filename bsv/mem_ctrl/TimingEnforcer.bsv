/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/TimingEnforcer.bsv
 * Description: JEDEC DDR5 AC timing enforcer, tracking per-bank state machines,
 *              row buffer locality, and tRCD, tRP, tRAS, and tWR latency constraints.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TimingEnforcer;

import Vector::*;
import ConfigReg::*;
import Ddr5Types::*;

interface TimingEnforcer;
   method Bool canIssueAct(GlobalBankIdx b);
   method Bool canIssueRead(GlobalBankIdx b, RowAddr r);
   method Bool canIssueWrite(GlobalBankIdx b, RowAddr r);
   method Bool canIssuePre(GlobalBankIdx b);

   method Action recordAct(GlobalBankIdx b, RowAddr r);
   method Action recordRead(GlobalBankIdx b);
   method Action recordWrite(GlobalBankIdx b);
   method Action recordPre(GlobalBankIdx b);

   method BankState getBankState(GlobalBankIdx b);
   method RowAddr   getActiveRow(GlobalBankIdx b);
endinterface

(* synthesize *)
module mkTimingEnforcer #(Ddr5TimingConfig timings) (TimingEnforcer);
   Vector#(32, Reg#(BankState)) bank_states <- replicateM(mkConfigReg(BANK_IDLE));
   Vector#(32, Reg#(RowAddr))   active_rows <- replicateM(mkConfigReg(0));
   Vector#(32, Reg#(UInt#(8)))  bank_timers <- replicateM(mkConfigReg(0));

   // Decrement countdown timers each clock cycle
   rule decrement_timers;
      for (Integer b = 0; b < 32; b = b + 1) begin
         if (bank_timers[b] > 0) begin
            bank_timers[b] <= bank_timers[b] - 1;
         end else begin
            // Automatic state transition when delay finishes
            if (bank_states[b] == BANK_ACTIVATING) begin
               bank_states[b] <= BANK_ACTIVE;
            end else if (bank_states[b] == BANK_PRECHARGING) begin
               bank_states[b] <= BANK_IDLE;
            end
         end
      end
   endrule

   method Bool canIssueAct(GlobalBankIdx b);
      return (bank_states[b] == BANK_IDLE && bank_timers[b] == 0);
   endmethod

   method Bool canIssueRead(GlobalBankIdx b, RowAddr r);
      return (bank_states[b] == BANK_ACTIVE && active_rows[b] == r && bank_timers[b] == 0);
   endmethod

   method Bool canIssueWrite(GlobalBankIdx b, RowAddr r);
      return (bank_states[b] == BANK_ACTIVE && active_rows[b] == r && bank_timers[b] == 0);
   endmethod

   method Bool canIssuePre(GlobalBankIdx b);
      return (bank_states[b] == BANK_ACTIVE && bank_timers[b] == 0);
   endmethod

   method Action recordAct(GlobalBankIdx b, RowAddr r);
      bank_states[b] <= BANK_ACTIVATING;
      active_rows[b] <= r;
      bank_timers[b] <= timings.t_rcd;
   endmethod

   method Action recordRead(GlobalBankIdx b);
      bank_timers[b] <= timings.t_ccd_s;
   endmethod

   method Action recordWrite(GlobalBankIdx b);
      bank_timers[b] <= timings.t_wr;
   endmethod

   method Action recordPre(GlobalBankIdx b);
      bank_states[b] <= BANK_PRECHARGING;
      bank_timers[b] <= timings.t_rp;
   endmethod

   method BankState getBankState(GlobalBankIdx b);
      return bank_states[b];
   endmethod

   method RowAddr getActiveRow(GlobalBankIdx b);
      return active_rows[b];
   endmethod
endmodule

endpackage: TimingEnforcer
