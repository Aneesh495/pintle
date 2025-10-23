/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mgmt/ThermalGovernor.bsv
 * Description: Dynamic thermal management unit monitoring on-die junction
 *              temperatures and enforcing duty-cycle credit throttling.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package ThermalGovernor;

typedef enum {
   THERM_NORMAL   = 2'b00,
   THERM_THROTTLE = 2'b01,
   THERM_CRITICAL = 2'b10
} ThermalState deriving (Bits, Eq, FShow);

interface ThermalGovernor;
   method Action setTemperature(Bit#(8) temp_celsius);
   method Action setThresholds(Bit#(8) warn_deg, Bit#(8) crit_deg, Bit#(8) hyst_deg);
   method Bit#(8) getTemperature();
   method Bit#(8) getWarnThreshold();
   method Bit#(8) getCritThreshold();
   method ThermalState getState();
   method Bool isThrottled();
   method Bool isCritical();
   method Action tick();
   method Bool permitTransaction();
endinterface

(* synthesize *)
module mkThermalGovernor (ThermalGovernor);
   Reg#(Bit#(8)) r_current_temp  <- mkReg(45); // Nominal idle 45 C
   Reg#(Bit#(8)) r_warn_thresh   <- mkReg(85); // Throttle at 85 C
   Reg#(Bit#(8)) r_crit_thresh   <- mkReg(105); // Emergency at 105 C
   Reg#(Bit#(8)) r_hysteresis    <- mkReg(5);  // De-throttle at 80 C
   Reg#(ThermalState) r_state    <- mkReg(THERM_NORMAL);
   Reg#(Bit#(4)) r_throttle_cnt  <- mkReg(0);

   rule update_thermal_state;
      let temp = r_current_temp;
      let warn = r_warn_thresh;
      let crit = r_crit_thresh;
      let hyst = r_hysteresis;

      if (temp >= crit) begin
         r_state <= THERM_CRITICAL;
      end
      else if (temp >= warn) begin
         r_state <= THERM_THROTTLE;
      end
      else if (r_state == THERM_CRITICAL) begin
         if (temp < (crit - hyst)) begin
            r_state <= (temp >= warn) ? THERM_THROTTLE : THERM_NORMAL;
         end
      end
      else if (r_state == THERM_THROTTLE) begin
         if (temp < (warn - hyst)) begin
            r_state <= THERM_NORMAL;
         end
      end
      else begin
         r_state <= THERM_NORMAL;
      end
   endrule

   method Action setTemperature(Bit#(8) temp_celsius);
      r_current_temp <= temp_celsius;
   endmethod

   method Action setThresholds(Bit#(8) warn_deg, Bit#(8) crit_deg, Bit#(8) hyst_deg);
      r_warn_thresh <= warn_deg;
      r_crit_thresh <= crit_deg;
      r_hysteresis  <= hyst_deg;
   endmethod

   method Bit#(8) getTemperature();
      return r_current_temp;
   endmethod

   method Bit#(8) getWarnThreshold();
      return r_warn_thresh;
   endmethod

   method Bit#(8) getCritThreshold();
      return r_crit_thresh;
   endmethod

   method ThermalState getState();
      return r_state;
   endmethod

   method Bool isThrottled();
      return (r_state != THERM_NORMAL);
   endmethod

   method Bool isCritical();
      return (r_state == THERM_CRITICAL);
   endmethod

   method Action tick();
      r_throttle_cnt <= r_throttle_cnt + 1;
   endmethod

   // In normal state: 100% throughput permitted.
   // In throttle state: 50% duty cycle (alternate even/odd cycles).
   // In critical state: 0% throughput permitted (halt).
   method Bool permitTransaction();
      if (r_state == THERM_NORMAL) begin
         return True;
      end
      else if (r_state == THERM_THROTTLE) begin
         return (r_throttle_cnt[0] == 1'b0);
      end
      else begin
         return False;
      end
   endmethod
endmodule

endpackage: ThermalGovernor
