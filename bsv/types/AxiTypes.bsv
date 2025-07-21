/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/types/AxiTypes.bsv
 * Description: AXI4-Lite and AXI4-Stream bus interface definitions for
 *              memory-mapped control registers and streaming hardware offloads.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package AxiTypes;



// ----------------------------------------------------------------------
// AXI4 Standard Response Encodings
// ----------------------------------------------------------------------

typedef Bit#(2) AxiResp;
AxiResp axi_RESP_OKAY   = 2'b00;
AxiResp axi_RESP_EXOKAY = 2'b01;
AxiResp axi_RESP_SLVERR = 2'b10;
AxiResp axi_RESP_DECERR = 2'b11;

// ----------------------------------------------------------------------
// AXI4-Lite Address and Data Channels
// ----------------------------------------------------------------------

typedef Bit#(32) AxiLiteAddr;
typedef Bit#(32) AxiLiteData;
typedef Bit#(4)  AxiLiteStrb;

typedef struct {
   AxiLiteAddr araddr;
   Bit#(3)     arprot;
} AxiLiteAR deriving (Bits, Eq, FShow);

typedef struct {
   AxiLiteData rdata;
   AxiResp     rresp;
} AxiLiteR deriving (Bits, Eq, FShow);

typedef struct {
   AxiLiteAddr awaddr;
   Bit#(3)     awprot;
} AxiLiteAW deriving (Bits, Eq, FShow);

typedef struct {
   AxiLiteData wdata;
   AxiLiteStrb wstrb;
} AxiLiteW deriving (Bits, Eq, FShow);

typedef struct {
   AxiResp     bresp;
} AxiLiteB deriving (Bits, Eq, FShow);

// Master and Slave Interface Bundles
interface AxiLiteMaster;
   method ActionValue#(AxiLiteAW) getAW();
   method ActionValue#(AxiLiteW)  getW();
   method Action                  putB(AxiLiteB b);
   method ActionValue#(AxiLiteAR) getAR();
   method Action                  putR(AxiLiteR r);
endinterface

interface AxiLiteSlave;
   method Action                  putAW(AxiLiteAW aw);
   method Action                  putW(AxiLiteW w);
   method ActionValue#(AxiLiteB)  getB();
   method Action                  putAR(AxiLiteAR ar);
   method ActionValue#(AxiLiteR)  getR();
endinterface

// ----------------------------------------------------------------------
// AXI4-Stream Interface for Data Movement and Offload Accelerators
// ----------------------------------------------------------------------

typedef Bit#(512) AxiStreamData;
typedef Bit#(64)  AxiStreamKeep;
typedef Bit#(16)  AxiStreamUser;

typedef struct {
   AxiStreamData data;
   AxiStreamKeep keep;
   Bool          last;
   AxiStreamUser user;
} AxiStreamPacket deriving (Bits, Eq, FShow);

interface AxiStreamSink;
   method Action putPacket(AxiStreamPacket pkt);
endinterface

interface AxiStreamSource;
   method ActionValue#(AxiStreamPacket) getPacket();
endinterface

endpackage: AxiTypes
