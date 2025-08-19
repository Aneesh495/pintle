/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/fabric/PortBasedRouter.bsv
 * Description: CXL 3.0 Port-Based Routing (PBR) table engine, decoding destination
 *              memory channel targets and enforcing multi-tenant isolation windows.
 *              Provides independent routing ports per host for conflict-free parallel access.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package PortBasedRouter;

import CxlTypes::*;

typedef struct {
   Bool valid;
   Addr base_addr;
   Addr limit_addr;
   Bool write_permitted;
} HostPartition deriving (Bits, Eq, FShow);

interface PortBasedRouter;
   method Action setPartition(HostId host, Addr base_a, Addr limit_a, Bool write_perm);
   method Maybe#(Bit#(2)) routeHost0(CxlMemM2SReq req);
   method Maybe#(Bit#(2)) routeHost1(CxlMemM2SReq req);
   method Maybe#(Bit#(2)) routeHost2(CxlMemM2SReq req);
   method Maybe#(Bit#(2)) routeHost3(CxlMemM2SReq req);
   method Maybe#(Bit#(2)) routeRequest(CxlMemM2SReq req);
endinterface

(* synthesize *)
module mkPortBasedRouter (PortBasedRouter);
   Reg#(HostPartition) part0 <- mkReg(HostPartition{valid: True, base_addr: 0, limit_addr: ~64'b0, write_permitted: True});
   Reg#(HostPartition) part1 <- mkReg(HostPartition{valid: True, base_addr: 0, limit_addr: ~64'b0, write_permitted: True});
   Reg#(HostPartition) part2 <- mkReg(HostPartition{valid: True, base_addr: 0, limit_addr: ~64'b0, write_permitted: True});
   Reg#(HostPartition) part3 <- mkReg(HostPartition{valid: True, base_addr: 0, limit_addr: ~64'b0, write_permitted: True});

   function Maybe#(Bit#(2)) checkPartition(HostPartition p, CxlMemM2SReq req);
      Bool in_bounds = (req.addr >= p.base_addr && req.addr <= p.limit_addr);
      Bool op_ok = (req.opcode == MEM_OP_READ || req.opcode == MEM_OP_READ_DATA) || p.write_permitted;
      if (p.valid && in_bounds && op_ok) begin
         let dec = decodeAddress(req.addr);
         return Valid(dec.channel);
      end else begin
         return Invalid;
      end
   endfunction

   method Action setPartition(HostId host, Addr base_a, Addr limit_a, Bool write_perm);
      HostPartition p = HostPartition {
         valid: True,
         base_addr: base_a,
         limit_addr: limit_a,
         write_permitted: write_perm
      };
      case (host[1:0])
         2'd0: part0 <= p;
         2'd1: part1 <= p;
         2'd2: part2 <= p;
         2'd3: part3 <= p;
      endcase
   endmethod

   method Maybe#(Bit#(2)) routeHost0(CxlMemM2SReq req);
      return checkPartition(part0, req);
   endmethod

   method Maybe#(Bit#(2)) routeHost1(CxlMemM2SReq req);
      return checkPartition(part1, req);
   endmethod

   method Maybe#(Bit#(2)) routeHost2(CxlMemM2SReq req);
      return checkPartition(part2, req);
   endmethod

   method Maybe#(Bit#(2)) routeHost3(CxlMemM2SReq req);
      return checkPartition(part3, req);
   endmethod

   method Maybe#(Bit#(2)) routeRequest(CxlMemM2SReq req);
      case (req.host_id[1:0])
         2'd0: return checkPartition(part0, req);
         2'd1: return checkPartition(part1, req);
         2'd2: return checkPartition(part2, req);
         2'd3: return checkPartition(part3, req);
      endcase
   endmethod
endmodule

endpackage: PortBasedRouter
