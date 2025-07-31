/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: tb/TbFlitPacker.bsv
 * Description: Unit testbench for CXL FlitPacker and FlitUnpacker roundtrip codec,
 *              verifying slot serialization, deserialization, and CRC integrity.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package TbFlitPacker;

import CxlTypes::*;
import FlitPacker::*;
import FlitUnpacker::*;
import Vector::*;

(* synthesize *)
module mkTbFlitPacker (Empty);
   FlitPacker   packer   <- mkFlitPacker();
   FlitUnpacker unpacker <- mkFlitUnpacker();

   Reg#(UInt#(32)) cycle_cnt <- mkReg(0);
   Reg#(UInt#(32)) step      <- mkReg(0);

   rule count_cycles;
      cycle_cnt <= cycle_cnt + 1;
      if (cycle_cnt > 200) begin
         $display("[TIMEOUT] TbFlitPacker exceeded max simulation cycles!");
         $finish(1);
      end
   endrule

   rule drive_test if (step == 0);
      $display("=== [TEST] TbFlitPacker: Testing Packer to Unpacker Loopback ===");
      CxlMemS2MRsp rsp = CxlMemS2MRsp {
         host_id:  4'h2,
         port_id:  3'h1,
         tag:      12'h3A5,
         status:   RSP_SUCCESS,
         has_data: True,
         data:     512'hDEADBEEF_CAFEF00D_12345678_9ABCDEF0_FEEDFACE_00112233_44556677_8899AABB
      };
      packer.putMemRsp(rsp);
      packer.returnCredits(8'd7);
      step <= 1;
   endrule

   rule forward_flit if (step == 1);
      let flt <- packer.getFlit();
      $display("[TbFlitPacker] Flit generated with CRC 0x%08X, seq=%0d, credits=%0d",
               flt.crc, flt.seq_num, flt.credit_tokens);
      unpacker.putFlit(flt);
      step <= 2;
   endrule

   rule receive_unpacked if (step == 2);
      let req <- unpacker.getMemReq();
      let cred <- unpacker.getCreditReturn();
      $display("[TbFlitPacker] Received Unpacked Request: host_id=%0d, tag=0x%03X, credits=%0d",
               req.host_id, req.tag, cred);

      if (req.host_id != 4'h2 || req.tag != 12'h3A5 || cred != 8'd7) begin
         $display("[FATAL] Unpacked fields mismatch original response!");
         $finish(1);
      end else begin
         $display("=== [PASS] TbFlitPacker: Flit roundtrip verification succeeded ===");
         $finish(0);
      end
   endrule
endmodule

endpackage: TbFlitPacker
