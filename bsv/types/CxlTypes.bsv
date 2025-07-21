/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/types/CxlTypes.bsv
 * Description: Fundamental types, address decomposition, and protocol structures
 *              for CXL.io, CXL.cache, and CXL.mem sub-protocols.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CxlTypes;

import Vector::*;

// ----------------------------------------------------------------------
// Fundamental Architectural Constants and Types
// ----------------------------------------------------------------------

typedef 4  NumHosts;
typedef 8  NumPorts;
typedef 64 CacheLineBytes;
typedef 512 CacheLineBits;

typedef Bit#(4)   HostId;
typedef Bit#(3)   PortId;
typedef Bit#(12)  TagId;
typedef Bit#(64)  Addr;
typedef Bit#(512) CacheLineData;
typedef Bit#(64)  ByteEn;
typedef Bit#(32)  Crc32;

// ----------------------------------------------------------------------
// Address Decomposition (System Physical Address mapping)
// [5:0]   : Byte Offset within 64-byte Cache Line
// [7:6]   : Channel Index (4 Channels)
// [9:8]   : Bank Group (4 Bank Groups per Channel)
// [12:10] : Bank Index (8 Banks per Bank Group)
// [13]    : Rank Index (2 Ranks per Channel)
// [31:14] : Row Address (18 bits = 256K Rows)
// [63:32] : Upper Tag Address
// ----------------------------------------------------------------------

typedef struct {
   Bit#(32) tag;
   Bit#(18) row;
   Bit#(1)  rank;
   Bit#(3)  bank;
   Bit#(2)  bank_group;
   Bit#(2)  channel;
   Bit#(6)  offset;
} DecodedAddr deriving (Bits, Eq, FShow);

function DecodedAddr decodeAddress(Addr a);
   return DecodedAddr {
      tag:        a[63:32],
      row:        a[31:14],
      rank:       a[13],
      bank:       a[12:10],
      bank_group: a[9:8],
      channel:    a[7:6],
      offset:     a[5:0]
   };
endfunction

function Addr encodeAddress(DecodedAddr d);
   return {d.tag, d.row, d.rank, d.bank, d.bank_group, d.channel, d.offset};
endfunction

function Addr lineAlignedAddress(Addr a);
   return {a[63:6], 6'b000000};
endfunction

// ----------------------------------------------------------------------
// CXL.mem Sub-Protocol Definitions (Master to Subordinate / Subordinate to Master)
// ----------------------------------------------------------------------

typedef enum {
   MEM_OP_READ,        // Standard coherent cache line read (MemRd)
   MEM_OP_READ_DATA,   // Read request with speculative payload (MemRdData)
   MEM_OP_WRITE,       // Posted cache line write (MemWr)
   MEM_OP_WRITE_DATA,  // Full cache line write with data (MemWrData)
   MEM_OP_INV,         // Invalidate line across host caches (MemInv)
   MEM_OP_CLEAN,       // Flush dirty data back to memory pool (MemCln)
   MEM_OP_FLUSH        // Clean and invalidate line across system (MemFlush)
} CxlMemOp deriving (Bits, Eq, FShow);

typedef enum {
   RSP_SUCCESS,        // Transaction completed successfully
   RSP_DATA_READY,     // Read data is available on data bus
   RSP_CONFLICT,       // Line address has an in-flight conflict
   RSP_ERROR_ECC,      // Uncorrectable double-bit memory error detected
   RSP_ERROR_TIMEOUT   // Link timeout or bus credit exhaustion
} CxlRspStatus deriving (Bits, Eq, FShow);

// CXL.mem M2S (Master-to-Subordinate) Request
typedef struct {
   HostId        host_id;
   PortId        port_id;
   TagId         tag;
   CxlMemOp      opcode;
   Addr          addr;
   ByteEn        byte_en;
   Bool          is_prefetch;
} CxlMemM2SReq deriving (Bits, Eq, FShow);

// CXL.mem S2M (Subordinate-to-Master) Response (NDR / DRS)
typedef struct {
   HostId        host_id;
   PortId        port_id;
   TagId         tag;
   CxlRspStatus  status;
   Bool          has_data;
   CacheLineData data;
} CxlMemS2MRsp deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// CXL.cache Sub-Protocol Definitions (Device to Host / Host to Device)
// ----------------------------------------------------------------------

typedef enum {
   CACHE_OP_RD_CURR,   // Read current value without changing ownership
   CACHE_OP_RD_OWN,    // Read ownership for exclusive modification
   CACHE_OP_RD_SHARED, // Read shared for non-exclusive caching
   CACHE_OP_INVAL,     // Device relinquishes cached line
   CACHE_OP_ITOM_WR,   // Invalidate-to-Modified write
   CACHE_OP_CL_FLUSH   // Cache line eviction flush
} CxlCacheOp deriving (Bits, Eq, FShow);

typedef struct {
   HostId        host_id;
   PortId        port_id;
   TagId         tag;
   CxlCacheOp    opcode;
   Addr          addr;
} CxlCacheD2HReq deriving (Bits, Eq, FShow);

typedef struct {
   HostId        host_id;
   PortId        port_id;
   TagId         tag;
   CxlRspStatus  status;
   CacheLineData data;
} CxlCacheH2DRsp deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// CXL 256-Byte Standard Flit Structure (CXL 3.0 / CXL 3.1)
// Each 256-byte flit contains 16 slots (16 bytes each), payload chunks,
// header, slot mapping, credit tokens, and 32-bit CRC.
// ----------------------------------------------------------------------

typedef 16 NumFlitSlots;
typedef Bit#(128) FlitSlot;

typedef struct {
   Bit#(8)               flit_type;     // Protocol format identifier
   Bit#(8)               seq_num;       // Monotonic sequence number for replay
   Bit#(8)               ack_num;       // Acknowledged sequence number
   Bit#(8)               credit_tokens; // Link credits returned to peer
   Vector#(14, FlitSlot) slots;         // 14 Payload and Protocol Slots
   Crc32                 crc;           // 32-bit CRC across entire flit
} CxlStandardFlit deriving (Bits, Eq, FShow);

endpackage: CxlTypes
