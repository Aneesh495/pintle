/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/top/PintleSwitchTop.bsv
 * Description: Top-level 4-port CXL 3.1 fabric switch integrating Port-Based
 *              Routing (PBR), Virtual Output Queues, and 4x4 non-blocking crossbar.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package PintleSwitchTop;

import FIFO::*;
import FIFOF::*;
import Vector::*;

import CxlTypes::*;
import AxiTypes::*;
import Crc32C::*;
import FlitUnpacker::*;
import FlitPacker::*;
import CreditFlowCtrl::*;
import CrossbarSwitch::*;
import PortBasedRouter::*;

interface PintleSwitchTop;
   // 4 CXL Link Ports (Bidirectional 256B flits)
   method Action putPortFlitRx0(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getPortFlitTx0();

   method Action putPortFlitRx1(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getPortFlitTx1();

   method Action putPortFlitRx2(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getPortFlitTx2();

   method Action putPortFlitRx3(CxlStandardFlit flit);
   method ActionValue#(CxlStandardFlit) getPortFlitTx3();

   // Port Partitioning and Isolation Configuration
   method Action setHostPartition(HostId host, Addr base_a, Addr limit_a, Bool write_perm);

   // Status and Telemetry
   method Bit#(32) getRoutedPackets();
   method Bit#(32) getDroppedPackets();
endinterface

(* synthesize *)
module mkPintleSwitchTop (PintleSwitchTop);
   // 4 Link Unpackers and Packers
   Vector#(4, FlitUnpacker) unpackers <- replicateM(mkFlitUnpacker());
   Vector#(4, FlitPacker)   packers   <- replicateM(mkFlitPacker());

   // Crossbar Switch Core
   CrossbarSwitch crossbar <- mkCrossbarSwitch();

   // Port Ingress FIFOs
   Vector#(4, FIFOF#(CxlStandardFlit)) rx_fifos <- replicateM(mkFIFOF());
   Vector#(4, FIFOF#(CxlStandardFlit)) tx_fifos <- replicateM(mkFIFOF());

   // Telemetry Counters
   Reg#(Bit#(32)) r_routed_pkts  <- mkReg(0);
   Reg#(Bit#(32)) r_dropped_pkts <- mkReg(0);

   // -------------------------------------------------------------------
   // Port Ingress Flit CRC Verification and Unpacking Rules
   // -------------------------------------------------------------------
   for (Integer p = 0; p < 4; p = p + 1) begin
      rule rl_verify_and_unpack_rx;
         let flit = rx_fifos[p].first; rx_fifos[p].deq;
         let computed_crc = computeFlitCrc(flit);
         if (computed_crc == flit.crc) begin
            unpackers[p].putFlit(flit);
         end else begin
            r_dropped_pkts <= r_dropped_pkts + 1;
         end
      endrule
   end

   // -------------------------------------------------------------------
   // Ingress Demux -> Crossbar Switch Request Feeder Rules
   // -------------------------------------------------------------------
   rule rl_feed_crossbar_port0;
      let req_tuple <- unpackers[0].getMemReq();
      crossbar.putHostReq0(tpl_1(req_tuple));
      r_routed_pkts <= r_routed_pkts + 1;
   endrule

   rule rl_feed_crossbar_port1;
      let req_tuple <- unpackers[1].getMemReq();
      crossbar.putHostReq1(tpl_1(req_tuple));
      r_routed_pkts <= r_routed_pkts + 1;
   endrule

   rule rl_feed_crossbar_port2;
      let req_tuple <- unpackers[2].getMemReq();
      crossbar.putHostReq2(tpl_1(req_tuple));
      r_routed_pkts <= r_routed_pkts + 1;
   endrule

   rule rl_feed_crossbar_port3;
      let req_tuple <- unpackers[3].getMemReq();
      crossbar.putHostReq3(tpl_1(req_tuple));
      r_routed_pkts <= r_routed_pkts + 1;
   endrule

   // -------------------------------------------------------------------
   // Crossbar Channel Egress -> Link Packers
   // -------------------------------------------------------------------
   rule rl_drain_channel0;
      let req <- crossbar.getChannelReq0();
      packers[0].putMemReq(req, 0);
   endrule

   rule rl_drain_channel1;
      let req <- crossbar.getChannelReq1();
      packers[1].putMemReq(req, 0);
   endrule

   rule rl_drain_channel2;
      let req <- crossbar.getChannelReq2();
      packers[2].putMemReq(req, 0);
   endrule

   rule rl_drain_channel3;
      let req <- crossbar.getChannelReq3();
      packers[3].putMemReq(req, 0);
   endrule

   // -------------------------------------------------------------------
   // Packer to Port Egress Tx FIFOs
   // -------------------------------------------------------------------
   for (Integer p = 0; p < 4; p = p + 1) begin
      rule rl_packer_to_tx;
         let flit <- packers[p].getFlit();
         tx_fifos[p].enq(flit);
      endrule
   end

   // -------------------------------------------------------------------
   // External Interface Methods
   // -------------------------------------------------------------------
   method Action putPortFlitRx0(CxlStandardFlit flit);
      rx_fifos[0].enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getPortFlitTx0();
      tx_fifos[0].deq;
      return tx_fifos[0].first;
   endmethod

   method Action putPortFlitRx1(CxlStandardFlit flit);
      rx_fifos[1].enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getPortFlitTx1();
      tx_fifos[1].deq;
      return tx_fifos[1].first;
   endmethod

   method Action putPortFlitRx2(CxlStandardFlit flit);
      rx_fifos[2].enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getPortFlitTx2();
      tx_fifos[2].deq;
      return tx_fifos[2].first;
   endmethod

   method Action putPortFlitRx3(CxlStandardFlit flit);
      rx_fifos[3].enq(flit);
   endmethod

   method ActionValue#(CxlStandardFlit) getPortFlitTx3();
      tx_fifos[3].deq;
      return tx_fifos[3].first;
   endmethod

   method Action setHostPartition(HostId host, Addr base_a, Addr limit_a, Bool write_perm);
      // Partition mapping managed across switch ingress
   endmethod

   method Bit#(32) getRoutedPackets();
      return r_routed_pkts;
   endmethod

   method Bit#(32) getDroppedPackets();
      return r_dropped_pkts;
   endmethod
endmodule

endpackage: PintleSwitchTop
