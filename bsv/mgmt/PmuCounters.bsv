/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mgmt/PmuCounters.bsv
 * Description: Performance Monitoring Unit (PMU) 64-bit event counters tracking
 *              flit throughput, cache directory hit rates, and ECC health.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package PmuCounters;

import Vector::*;
import CxlTypes::*;

typedef enum {
   PMU_EVT_FLIT_RX,
   PMU_EVT_FLIT_TX,
   PMU_EVT_MEM_READ,
   PMU_EVT_MEM_WRITE,
   PMU_EVT_DIR_HIT,
   PMU_EVT_DIR_MISS,
   PMU_EVT_BI_SNOOP,
   PMU_EVT_ECC_1BIT,
   PMU_EVT_ECC_2BIT,
   PMU_EVT_CREDIT_STALL
} PmuEvent deriving (Bits, Eq, FShow);

interface PmuCounters;
   method Action incrementEvent(PmuEvent evt);
   method Bit#(64) readCounter(PmuEvent evt);
   method Action resetAllCounters();
endinterface

(* synthesize *)
module mkPmuCounters (PmuCounters);
   Vector#(10, Reg#(Bit#(64))) event_counters <- replicateM(mkReg(0));

   method Action incrementEvent(PmuEvent evt);
      Bit#(4) idx = zeroExtend(pack(evt));
      event_counters[idx] <= event_counters[idx] + 1;
   endmethod

   method Bit#(64) readCounter(PmuEvent evt);
      Bit#(4) idx = zeroExtend(pack(evt));
      return event_counters[idx];
   endmethod

   method Action resetAllCounters();
      for (Integer i = 0; i < 10; i = i + 1) begin
         event_counters[i] <= 0;
      end
   endmethod
endmodule

endpackage: PmuCounters
