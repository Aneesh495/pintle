/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mgmt/CxlCsrBank.bsv
 * Description: AXI4-Lite Control and Status Register (CSR) slave bank exposing
 *              CXL 3.1 DVSEC configuration, memory base, thermal throttling,
 *              scrubber parameters, and 64-bit PMU event counters.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CxlCsrBank;

import FIFO::*;
import FIFOF::*;
import Vector::*;
import AxiTypes::*;
import PmuCounters::*;
import ThermalGovernor::*;

interface CxlCsrBank;
   interface AxiLiteSlave axiSlave;

   // Control status exposed to PINTLE subsystems
   method Bool isCxlMemEnabled();
   method Bool isCxlCacheEnabled();
   method Bool isIdeEnabled();
   method Bool isLz4Enabled();
   method Bool isFilterEnabled();
   method Bit#(64) getMemBaseAddress();
   method Bit#(32) getScrubInterval();
   method Bool isScrubEnabled();
   method Bool isThrottled();
   method Bool isCritical();

   // Event pulses from datapath subsystems
   method Action recordEccSingle();
   method Action recordEccDouble();
   method Action incrementPmu(PmuEvent evt);
   method Action updateJunctionTemp(Bit#(8) temp);
endinterface

(* synthesize *)
module mkCxlCsrBank (CxlCsrBank);
   // AXI-Lite Channel FIFOs
   FIFOF#(AxiLiteAW) fifo_aw <- mkFIFOF;
   FIFOF#(AxiLiteW)  fifo_w  <- mkFIFOF;
   FIFOF#(AxiLiteB)  fifo_b  <- mkFIFOF;
   FIFOF#(AxiLiteAR) fifo_ar <- mkFIFOF;
   FIFOF#(AxiLiteR)  fifo_r  <- mkFIFOF;

   // Submodules
   PmuCounters      pmu     <- mkPmuCounters;
   ThermalGovernor  thermal <- mkThermalGovernor;

   // Registers
   Reg#(Bit#(32)) r_cxl_ctrl       <- mkReg(32'h0000_003F); // All protocols enabled by default
   Reg#(Bit#(32)) r_mem_base_lo    <- mkReg(32'h0000_0000);
   Reg#(Bit#(32)) r_mem_base_hi    <- mkReg(32'h0000_0000);
   Reg#(Bit#(32)) r_scrub_interval <- mkReg(32'h0000_1000); // 4096 cycles default
   Reg#(Bit#(32)) r_scrub_ctrl     <- mkReg(32'h0000_0001); // Scrub enable
   Reg#(Bit#(4))  r_pmu_sel        <- mkReg(0);
   Reg#(Bit#(32)) r_ecc_single_cnt <- mkReg(0);
   Reg#(Bit#(32)) r_ecc_double_cnt <- mkReg(0);

   // AXI4-Lite Write Handler Rule
   rule rl_handle_write (fifo_aw.notEmpty && fifo_w.notEmpty && fifo_b.notFull);
      let aw = fifo_aw.first; fifo_aw.deq;
      let w  = fifo_w.first;  fifo_w.deq;

      AxiResp resp = axi_RESP_OKAY;
      Bit#(16) offset = aw.awaddr[15:0];

      case (offset)
         16'h0004: r_cxl_ctrl       <= w.wdata;
         16'h000C: r_mem_base_lo    <= w.wdata;
         16'h0010: r_mem_base_hi    <= w.wdata;
         16'h0018: r_scrub_interval <= w.wdata;
         16'h001C: r_scrub_ctrl     <= w.wdata;
         16'h0020: thermal.setTemperature(w.wdata[7:0]);
         16'h0024: thermal.setThresholds(w.wdata[7:0], w.wdata[15:8], w.wdata[23:16]);
         16'h0030: r_pmu_sel        <= w.wdata[3:0];
         16'h003C: begin
            if (w.wdata[0] == 1'b1) begin
               pmu.resetAllCounters();
            end
         end
         default: resp = axi_RESP_OKAY;
      endcase

      AxiLiteB b_resp;
      b_resp.bresp = resp;
      fifo_b.enq(b_resp);
   endrule

   // AXI4-Lite Read Handler Rule
   rule rl_handle_read (fifo_ar.notEmpty && fifo_r.notFull);
      let ar = fifo_ar.first; fifo_ar.deq;

      AxiLiteData rdata = 0;
      AxiResp resp = axi_RESP_OKAY;
      Bit#(16) offset = ar.araddr[15:0];

      PmuEvent sel_evt = unpack(r_pmu_sel);
      Bit#(64) pmu_val = pmu.readCounter(sel_evt);

      case (offset)
         16'h0000: rdata = 32'hC310_1E37; // PINTLE CXL 3.1 Device Signature
         16'h0004: rdata = r_cxl_ctrl;
         16'h0008: rdata = 32'h0000_0007; // Link Up, Mem Ready, Coherence Active
         16'h000C: rdata = r_mem_base_lo;
         16'h0010: rdata = r_mem_base_hi;
         16'h0014: rdata = 32'd64;        // 64 GB Pool Capacity
         16'h0018: rdata = r_scrub_interval;
         16'h001C: rdata = r_scrub_ctrl;
         16'h0020: rdata = zeroExtend(thermal.getTemperature());
         16'h0024: rdata = {8'h00, 8'd5, thermal.getCritThreshold(), thermal.getWarnThreshold()};
         16'h0028: rdata = {28'h0,
                           (thermal.isCritical() ? 1'b1 : 1'b0),
                           (thermal.isThrottled() ? 1'b1 : 1'b0),
                           pack(thermal.getState())};
         16'h0030: rdata = zeroExtend(r_pmu_sel);
         16'h0034: rdata = pmu_val[31:0];
         16'h0038: rdata = pmu_val[63:32];
         16'h003C: rdata = 32'h0;
         16'h0040: rdata = r_ecc_single_cnt;
         16'h0044: rdata = r_ecc_double_cnt;
         default:  begin
            rdata = 32'hDEAD_BEEF;
            resp = axi_RESP_DECERR;
         end
      endcase

      AxiLiteR r_resp;
      r_resp.rdata = rdata;
      r_resp.rresp = resp;
      fifo_r.enq(r_resp);
   endrule

   // AXI4-Lite Slave Interface
   interface AxiLiteSlave axiSlave;
      method Action putAW(AxiLiteAW aw);
         fifo_aw.enq(aw);
      endmethod

      method Action putW(AxiLiteW w);
         fifo_w.enq(w);
      endmethod

      method ActionValue#(AxiLiteB) getB();
         fifo_b.deq;
         return fifo_b.first;
      endmethod

      method Action putAR(AxiLiteAR ar);
         fifo_ar.enq(ar);
      endmethod

      method ActionValue#(AxiLiteR) getR();
         fifo_r.deq;
         return fifo_r.first;
      endmethod
   endinterface

   method Bool isCxlMemEnabled();
      return (r_cxl_ctrl[2] == 1'b1);
   endmethod

   method Bool isCxlCacheEnabled();
      return (r_cxl_ctrl[1] == 1'b1);
   endmethod

   method Bool isIdeEnabled();
      return (r_cxl_ctrl[3] == 1'b1);
   endmethod

   method Bool isLz4Enabled();
      return (r_cxl_ctrl[4] == 1'b1);
   endmethod

   method Bool isFilterEnabled();
      return (r_cxl_ctrl[5] == 1'b1);
   endmethod

   method Bit#(64) getMemBaseAddress();
      return {r_mem_base_hi, r_mem_base_lo};
   endmethod

   method Bit#(32) getScrubInterval();
      return r_scrub_interval;
   endmethod

   method Bool isScrubEnabled();
      return (r_scrub_ctrl[0] == 1'b1);
   endmethod

   method Bool isThrottled();
      return thermal.isThrottled();
   endmethod

   method Bool isCritical();
      return thermal.isCritical();
   endmethod

   method Action recordEccSingle();
      r_ecc_single_cnt <= r_ecc_single_cnt + 1;
      pmu.incrementEvent(PMU_EVT_ECC_1BIT);
   endmethod

   method Action recordEccDouble();
      r_ecc_double_cnt <= r_ecc_double_cnt + 1;
      pmu.incrementEvent(PMU_EVT_ECC_2BIT);
   endmethod

   method Action incrementPmu(PmuEvent evt);
      pmu.incrementEvent(evt);
   endmethod

   method Action updateJunctionTemp(Bit#(8) temp);
      thermal.setTemperature(temp);
   endmethod
endmodule

endpackage: CxlCsrBank
