/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/coherence/BiasEngine.bsv
 * Description: Dynamic Device Bias tracking engine with locality hysteresis,
 *              coordinating transitions between Host-Bias and Device-Bias modes.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package BiasEngine;

import Vector::*;
import RegFile::*;
import CxlTypes::*;
import CoherenceTypes::*;

typedef 64 NumBiasRegions; // 64 memory regions tracked for bias locality
typedef Bit#(6) BiasRegionIdx;

interface BiasEngine;
   method Action recordHostAccess(Addr a);
   method Action recordDeviceAccess(Addr a);
   method Bool isDeviceBias(Addr a);
   method Maybe#(Tuple2#(Addr, Bool)) getPendingBiasFlip();
   method Action acknowledgeFlip();
endinterface

(* synthesize *)
module mkBiasEngine (BiasEngine);
   // 4-bit saturating counters per region (0 = strong host bias, 15 = strong device bias)
   RegFile#(BiasRegionIdx, UInt#(4)) locality_counters <- mkRegFileFull();
   RegFile#(BiasRegionIdx, Bool)     region_dev_bias   <- mkRegFileFull();

   Reg#(Maybe#(Tuple2#(Addr, Bool))) pending_flip <- mkReg(Invalid);

   function BiasRegionIdx getRegion(Addr a);
      return a[17:12]; // 4KB page region mapping
   endfunction

   method Action recordHostAccess(Addr a);
      let r = getRegion(a);
      let c = locality_counters.sub(r);
      let current_bias = region_dev_bias.sub(r);

      let new_c = (c > 0) ? (c - 1) : 0;
      locality_counters.upd(r, new_c);

      // If counter drops below threshold (4) while in device bias, flip to host bias
      if (current_bias && new_c < 4 && !isValid(pending_flip)) begin
         region_dev_bias.upd(r, False);
         pending_flip <= Valid(tuple2(a, False));
      end
   endmethod

   method Action recordDeviceAccess(Addr a);
      let r = getRegion(a);
      let c = locality_counters.sub(r);
      let current_bias = region_dev_bias.sub(r);

      let new_c = (c < 15) ? (c + 1) : 15;
      locality_counters.upd(r, new_c);

      // If counter exceeds threshold (11) while in host bias, flip to device bias
      if (!current_bias && new_c > 11 && !isValid(pending_flip)) begin
         region_dev_bias.upd(r, True);
         pending_flip <= Valid(tuple2(a, True));
      end
   endmethod

   method Bool isDeviceBias(Addr a);
      let r = getRegion(a);
      return region_dev_bias.sub(r);
   endmethod

   method Maybe#(Tuple2#(Addr, Bool)) getPendingBiasFlip();
      return pending_flip;
   endmethod

   method Action acknowledgeFlip();
      pending_flip <= Invalid;
   endmethod
endmodule

endpackage: BiasEngine
