/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/types/CoherenceTypes.bsv
 * Description: Directory-based multi-host cache coherence types, Back-Invalidation
 *              (BI) protocol encodings, and Miss Status Holding Register (MSHR) records.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CoherenceTypes;

import CxlTypes::*;

// ----------------------------------------------------------------------
// Coherence States (Extended MESI / MOESI protocol)
// ----------------------------------------------------------------------

typedef enum {
   COH_INVALID,   // Cache line is not present or invalid across hosts
   COH_SHARED,    // Cache line is shared clean by one or more hosts
   COH_EXCLUSIVE, // Cache line is held exclusively by a single host (clean)
   COH_MODIFIED   // Cache line is held modified by a single host (dirty)
} CoherenceState deriving (Bits, Eq, FShow);

typedef Bit#(8) SharerMask; // Bit vector of connected hosts (up to 8 hosts)

function Bool isSharer(SharerMask mask, HostId host);
   return (mask[host] == 1'b1);
endfunction

function SharerMask addSharer(SharerMask mask, HostId host);
   Bit#(8) shifted = 8'b1 << host;
   return (mask | shifted);
endfunction

function SharerMask removeSharer(SharerMask mask, HostId host);
   Bit#(8) shifted = ~(8'b1 << host);
   return (mask & shifted);
endfunction

function Bool hasSharers(SharerMask mask);
   return (mask != 0);
endfunction

function UInt#(4) countSharers(SharerMask mask);
   UInt#(4) count = 0;
   for (Integer i = 0; i < 8; i = i + 1) begin
      if (mask[i] == 1'b1) count = count + 1;
   end
   return count;
endfunction

// ----------------------------------------------------------------------
// Back-Invalidation (BI) Messages (CXL.mem BI Channel)
// ----------------------------------------------------------------------

typedef enum {
   BI_SNP_INV,    // Force peer host to invalidate local copy
   BI_SNP_CUR,    // Snoop current value without forcing invalidation
   BI_SNP_DATA    // Force peer host to writeback dirty line and invalidate
} BackInvalidateOp deriving (Bits, Eq, FShow);

typedef enum {
   BI_RSP_CLEAN,  // Peer acknowledged invalidation, line was clean
   BI_RSP_DIRTY,  // Peer wrote back modified dirty data
   BI_RSP_MISS    // Peer did not have line in local cache
} BackInvalidateRspStatus deriving (Bits, Eq, FShow);

typedef struct {
   HostId           dest_host;
   TagId            tag;
   BackInvalidateOp opcode;
   Addr             addr;
} BackInvalidateReq deriving (Bits, Eq, FShow);

typedef struct {
   HostId                 src_host;
   TagId                  tag;
   BackInvalidateRspStatus status;
   Bool                   has_dirty_data;
   CacheLineData          dirty_data;
} BackInvalidateRsp deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// Directory Cache Structures
// ----------------------------------------------------------------------

typedef struct {
   Bool           valid;
   Bit#(32)       tag;
   CoherenceState state;
   SharerMask     sharers;
   HostId         owner;
   Bool           is_device_bias; // Host-bias (0) or Device-bias (1)
} DirectoryEntry deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// Miss Status Holding Register (MSHR) for In-Flight Coherence Serialization
// ----------------------------------------------------------------------

typedef 16 NumMshrEntries;
typedef Bit#(4) MshrIdx;

typedef enum {
   MSHR_IDLE,
   MSHR_DIR_LOOKUP,
   MSHR_WAIT_BI_RSP,
   MSHR_MEM_READ,
   MSHR_MEM_WRITE,
   MSHR_SEND_RSP
} MshrPhase deriving (Bits, Eq, FShow);

typedef struct {
   Bool          valid;
   Addr          addr;
   HostId        req_host;
   TagId         req_tag;
   CxlMemOp      req_op;
   MshrPhase     phase;
   SharerMask    pending_bi_mask;
   CacheLineData line_data;
   Bool          dirty_writeback;
   ByteEn        byte_en;
} MshrEntry deriving (Bits, Eq, FShow);

endpackage: CoherenceTypes
