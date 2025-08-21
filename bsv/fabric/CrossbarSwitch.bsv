/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/fabric/CrossbarSwitch.bsv
 * Description: 4-Port Host to 4-Channel Memory non-blocking crossbar matrix
 *              with Virtual Output Queues and round-robin arbiters.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CrossbarSwitch;

import FIFOF::*;
import Vector::*;
import CxlTypes::*;
import Arbiter::*;
import VirtualOutputQueue::*;
import PortBasedRouter::*;

interface CrossbarSwitch;
   // Indexed interface methods
   method Action putHostReq(Bit#(2) host_port, CxlMemM2SReq req);
   method ActionValue#(CxlMemM2SReq) getChannelReq(Bit#(2) channel);
   method Action putChannelRsp(Bit#(2) channel, CxlMemS2MRsp rsp);
   method ActionValue#(CxlMemS2MRsp) getHostRsp(Bit#(2) host_port);

   // Direct parallel access methods for concurrent multi-port driving
   method Action putHostReq0(CxlMemM2SReq req);
   method Action putHostReq1(CxlMemM2SReq req);
   method Action putHostReq2(CxlMemM2SReq req);
   method Action putHostReq3(CxlMemM2SReq req);

   method ActionValue#(CxlMemM2SReq) getChannelReq0();
   method ActionValue#(CxlMemM2SReq) getChannelReq1();
   method ActionValue#(CxlMemM2SReq) getChannelReq2();
   method ActionValue#(CxlMemM2SReq) getChannelReq3();
endinterface

(* synthesize *)
module mkCrossbarSwitch (CrossbarSwitch);
   PortBasedRouter router <- mkPortBasedRouter();

   // 4 Virtual Output Queues (one VOQ per Host Port)
   Vector#(4, Voq4Channel) host_voqs <- replicateM(mkVoq4Channel());

   // 4 Channel Request Output FIFOs
   Vector#(4, FIFOF#(CxlMemM2SReq)) ch_out_fifos <- replicateM(mkFIFOF());

   // 4 Channel Round-Robin Arbiters
   Vector#(4, RoundRobinArbiter4) ch_arbiters <- replicateM(mkRoundRobinArbiter4());

   // 4 Host Response Output FIFOs
   Vector#(4, FIFOF#(CxlMemS2MRsp)) host_rsp_fifos <- replicateM(mkFIFOF());

   // Arbitration rule for Channel 0
   rule arbitrate_ch0;
      Bit#(4) req_mask = 0;
      for (Integer h = 0; h < 4; h = h + 1) begin
         if (host_voqs[h].channels[0].notEmpty()) req_mask[h] = 1'b1;
      end
      ch_arbiters[0].request(req_mask);
      let grant = ch_arbiters[0].getGrant();
      if (isValid(grant) && ch_out_fifos[0].notFull()) begin
         Bit#(2) gh = fromMaybe(0, grant);
         let req = host_voqs[gh].channels[0].first();
         host_voqs[gh].channels[0].deq();
         ch_out_fifos[0].enq(req);
         ch_arbiters[0].advanceGrant();
      end
   endrule

   // Arbitration rule for Channel 1
   rule arbitrate_ch1;
      Bit#(4) req_mask = 0;
      for (Integer h = 0; h < 4; h = h + 1) begin
         if (host_voqs[h].channels[1].notEmpty()) req_mask[h] = 1'b1;
      end
      ch_arbiters[1].request(req_mask);
      let grant = ch_arbiters[1].getGrant();
      if (isValid(grant) && ch_out_fifos[1].notFull()) begin
         Bit#(2) gh = fromMaybe(0, grant);
         let req = host_voqs[gh].channels[1].first();
         host_voqs[gh].channels[1].deq();
         ch_out_fifos[1].enq(req);
         ch_arbiters[1].advanceGrant();
      end
   endrule

   // Arbitration rule for Channel 2
   rule arbitrate_ch2;
      Bit#(4) req_mask = 0;
      for (Integer h = 0; h < 4; h = h + 1) begin
         if (host_voqs[h].channels[2].notEmpty()) req_mask[h] = 1'b1;
      end
      ch_arbiters[2].request(req_mask);
      let grant = ch_arbiters[2].getGrant();
      if (isValid(grant) && ch_out_fifos[2].notFull()) begin
         Bit#(2) gh = fromMaybe(0, grant);
         let req = host_voqs[gh].channels[2].first();
         host_voqs[gh].channels[2].deq();
         ch_out_fifos[2].enq(req);
         ch_arbiters[2].advanceGrant();
      end
   endrule

   // Arbitration rule for Channel 3
   rule arbitrate_ch3;
      Bit#(4) req_mask = 0;
      for (Integer h = 0; h < 4; h = h + 1) begin
         if (host_voqs[h].channels[3].notEmpty()) req_mask[h] = 1'b1;
      end
      ch_arbiters[3].request(req_mask);
      let grant = ch_arbiters[3].getGrant();
      if (isValid(grant) && ch_out_fifos[3].notFull()) begin
         Bit#(2) gh = fromMaybe(0, grant);
         let req = host_voqs[gh].channels[3].first();
         host_voqs[gh].channels[3].deq();
         ch_out_fifos[3].enq(req);
         ch_arbiters[3].advanceGrant();
      end
   endrule

   method Action putHostReq(Bit#(2) host_port, CxlMemM2SReq req);
      let maybe_dest = router.routeRequest(req);
      Bit#(2) dest_ch = fromMaybe(0, maybe_dest);
      host_voqs[host_port].enqToChannel(dest_ch, req);
   endmethod

   method Action putHostReq0(CxlMemM2SReq req);
      let maybe_dest = router.routeHost0(req);
      Bit#(2) dest_ch = fromMaybe(0, maybe_dest);
      host_voqs[0].enqToChannel(dest_ch, req);
   endmethod

   method Action putHostReq1(CxlMemM2SReq req);
      let maybe_dest = router.routeHost1(req);
      Bit#(2) dest_ch = fromMaybe(0, maybe_dest);
      host_voqs[1].enqToChannel(dest_ch, req);
   endmethod

   method Action putHostReq2(CxlMemM2SReq req);
      let maybe_dest = router.routeHost2(req);
      Bit#(2) dest_ch = fromMaybe(0, maybe_dest);
      host_voqs[2].enqToChannel(dest_ch, req);
   endmethod

   method Action putHostReq3(CxlMemM2SReq req);
      let maybe_dest = router.routeHost3(req);
      Bit#(2) dest_ch = fromMaybe(0, maybe_dest);
      host_voqs[3].enqToChannel(dest_ch, req);
   endmethod

   method ActionValue#(CxlMemM2SReq) getChannelReq(Bit#(2) channel);
      ch_out_fifos[channel].deq();
      return ch_out_fifos[channel].first();
   endmethod

   method ActionValue#(CxlMemM2SReq) getChannelReq0();
      ch_out_fifos[0].deq();
      return ch_out_fifos[0].first();
   endmethod

   method ActionValue#(CxlMemM2SReq) getChannelReq1();
      ch_out_fifos[1].deq();
      return ch_out_fifos[1].first();
   endmethod

   method ActionValue#(CxlMemM2SReq) getChannelReq2();
      ch_out_fifos[2].deq();
      return ch_out_fifos[2].first();
   endmethod

   method ActionValue#(CxlMemM2SReq) getChannelReq3();
      ch_out_fifos[3].deq();
      return ch_out_fifos[3].first();
   endmethod

   method Action putChannelRsp(Bit#(2) channel, CxlMemS2MRsp rsp);
      Bit#(2) dest_host = rsp.host_id[1:0];
      host_rsp_fifos[dest_host].enq(rsp);
   endmethod

   method ActionValue#(CxlMemS2MRsp) getHostRsp(Bit#(2) host_port);
      host_rsp_fifos[host_port].deq();
      return host_rsp_fifos[host_port].first();
   endmethod
endmodule

endpackage: CrossbarSwitch
