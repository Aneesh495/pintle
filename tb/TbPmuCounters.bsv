/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbPmuCounters.bsv
 * Description: Unit testbench verifying AXI4-Lite CSR bank, thermal throttling,
 *              and 64-bit PMU event counter increments.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbPmuCounters;

import StmtFSM::*;
import AxiTypes::*;
import PmuCounters::*;
import ThermalGovernor::*;
import CxlCsrBank::*;

(* synthesize *)
module mkTbPmuCounters (Empty);
   CxlCsrBank csr <- mkCxlCsrBank;

   Reg#(Bit#(32)) r_read_val <- mkReg(0);
   Reg#(Bit#(32)) step_cnt   <- mkReg(0);

   function AxiLiteAW makeAW(Bit#(32) addr);
      AxiLiteAW aw;
      aw.awaddr = addr;
      aw.awprot = 0;
      return aw;
   endfunction

   function AxiLiteW makeW(Bit#(32) data);
      AxiLiteW w;
      w.wdata = data;
      w.wstrb = 4'hF;
      return w;
   endfunction

   function AxiLiteAR makeAR(Bit#(32) addr);
      AxiLiteAR ar;
      ar.araddr = addr;
      ar.arprot = 0;
      return ar;
   endfunction

   Stmt test_seq = seq
      $display("[TbPmuCounters] Starting CSR and PMU Subsystem Verification...");

      // Step 1: Read Device ID (expect 32'hC310_1E37)
      csr.axiSlave.putAR(makeAR(32'h0000));
      action
         let r <- csr.axiSlave.getR();
         $display("[TbPmuCounters] Read Dev ID: 0x%08X (Expected 0xC3101E37)", r.rdata);
         if (r.rdata != 32'hC310_1E37) begin
            $display("[FAIL] Unexpected Dev ID!");
            $finish(1);
         end
      endaction

      // Step 2: Read Pool Capacity (expect 64 GB)
      csr.axiSlave.putAR(makeAR(32'h0014));
      action
         let r <- csr.axiSlave.getR();
         $display("[TbPmuCounters] Read Pool Capacity: %0d GB (Expected 64)", r.rdata);
         if (r.rdata != 32'd64) begin
            $display("[FAIL] Unexpected capacity!");
            $finish(1);
         end
      endaction

      // Step 3: Write and Read Memory Base Address (e.g. 0x0000_0001_8000_0000)
      csr.axiSlave.putAW(makeAW(32'h000C));
      csr.axiSlave.putW(makeW(32'h8000_0000));
      action
         let b <- csr.axiSlave.getB();
      endaction

      csr.axiSlave.putAW(makeAW(32'h0010));
      csr.axiSlave.putW(makeW(32'h0000_0001));
      action
         let b <- csr.axiSlave.getB();
      endaction

      action
         Bit#(64) base_addr = csr.getMemBaseAddress();
         $display("[TbPmuCounters] Configured Mem Base: 0x%016X", base_addr);
         if (base_addr != 64'h0000_0001_8000_0000) begin
            $display("[FAIL] Base address mismatch!");
            $finish(1);
         end
      endaction

      // Step 4: PMU event counting
      $display("[TbPmuCounters] Testing PMU event counters...");
      csr.incrementPmu(PMU_EVT_FLIT_RX);
      csr.incrementPmu(PMU_EVT_FLIT_RX);
      csr.incrementPmu(PMU_EVT_FLIT_RX);
      csr.incrementPmu(PMU_EVT_MEM_READ);
      csr.recordEccSingle();
      csr.recordEccSingle();
      csr.recordEccDouble();

      // Read back PMU FLIT_RX (event 0) via CSR
      csr.axiSlave.putAW(makeAW(32'h0030));
      csr.axiSlave.putW(makeW(32'd0)); // Select event 0
      action
         let b <- csr.axiSlave.getB();
      endaction

      csr.axiSlave.putAR(makeAR(32'h0034));
      action
         let r <- csr.axiSlave.getR();
         $display("[TbPmuCounters] PMU FLIT_RX Count: %0d (Expected 3)", r.rdata);
         if (r.rdata != 32'd3) begin
            $display("[FAIL] PMU count mismatch!");
            $finish(1);
         end
      endaction

      // Read back Single-bit ECC count
      csr.axiSlave.putAR(makeAR(32'h0040));
      action
         let r <- csr.axiSlave.getR();
         $display("[TbPmuCounters] ECC 1-bit Count: %0d (Expected 2)", r.rdata);
         if (r.rdata != 32'd2) begin
            $display("[FAIL] ECC single mismatch!");
            $finish(1);
         end
      endaction

      // Read back Double-bit ECC count
      csr.axiSlave.putAR(makeAR(32'h0044));
      action
         let r <- csr.axiSlave.getR();
         $display("[TbPmuCounters] ECC 2-bit Count: %0d (Expected 1)", r.rdata);
         if (r.rdata != 32'd1) begin
            $display("[FAIL] ECC double mismatch!");
            $finish(1);
         end
      endaction

      // Step 5: Test Thermal Governor response
      $display("[TbPmuCounters] Testing Thermal Governor response...");
      csr.updateJunctionTemp(88); // 88 C (>= 85 warn)
      // Wait 2 cycles for state update
      noAction;
      noAction;
      action
         Bool throttled = csr.isThrottled();
         Bool critical  = csr.isCritical();
         $display("[TbPmuCounters] Temp 88C: throttled=%b, critical=%b (Expected throttled=1, crit=0)",
                  throttled, critical);
         if (!throttled || critical) begin
            $display("[FAIL] Thermal state incorrect at 88C!");
            $finish(1);
         end
      endaction

      csr.updateJunctionTemp(108); // 108 C (>= 105 crit)
      noAction;
      noAction;
      action
         Bool throttled = csr.isThrottled();
         Bool critical  = csr.isCritical();
         $display("[TbPmuCounters] Temp 108C: throttled=%b, critical=%b (Expected throttled=1, crit=1)",
                  throttled, critical);
         if (!critical) begin
            $display("[FAIL] Thermal state incorrect at 108C!");
            $finish(1);
         end
      endaction

      csr.updateJunctionTemp(70); // Cool down below hysteresis
      noAction;
      noAction;
      action
         Bool throttled = csr.isThrottled();
         Bool critical  = csr.isCritical();
         $display("[TbPmuCounters] Temp 70C: throttled=%b, critical=%b (Expected throttled=0, crit=0)",
                  throttled, critical);
         if (throttled || critical) begin
            $display("[FAIL] Thermal state failed to return to normal at 70C!");
            $finish(1);
         end
      endaction

      $display("[TbPmuCounters] ALL CSR AND PMU TESTS PASSED SUCCESSFULLY!");
      $finish(0);
   endseq;

   mkAutoFSM(test_seq);
endmodule

endpackage: TbPmuCounters
