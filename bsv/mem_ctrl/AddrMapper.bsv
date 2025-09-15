/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/mem_ctrl/AddrMapper.bsv
 * Description: Address mapping and XOR bank hashing engine, distributing System
 *              Physical Addresses (SPA) evenly across DDR5 channels, groups, and banks.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package AddrMapper;

import CxlTypes::*;
import Ddr5Types::*;

interface AddrMapper;
   method Ddr5MemRequest mapRequest(CxlMemM2SReq req, CacheLineData wr_data);
endinterface

(* synthesize *)
module mkAddrMapper (AddrMapper);
   method Ddr5MemRequest mapRequest(CxlMemM2SReq req, CacheLineData wr_data);
      Addr a = req.addr;

      // Extract raw bit fields
      ChannelIdx   ch  = a[7:6];
      BankGroupIdx bg  = a[9:8];
      BankIdx      bk  = a[12:10];
      RankIdx      rk  = a[13];
      RowAddr      row = a[31:14];
      ColAddr      col = {a[63:58], a[5:2]}; // High tag entropy hashed into lower column

      // XOR Bank Interleaving Hash: decorrelate stride-access bank collisions
      BankGroupIdx hashed_bg = bg ^ a[15:14];
      BankIdx      hashed_bk = bk ^ a[18:16];

      Bool is_wr = (req.opcode == MEM_OP_WRITE || req.opcode == MEM_OP_WRITE_DATA);

      return Ddr5MemRequest {
         channel:    ch,
         rank:       rk,
         bank_group: hashed_bg,
         bank:       hashed_bk,
         row:        row,
         col:        col,
         is_write:   is_wr,
         write_data: wr_data,
         byte_en:    req.byte_en,
         req_id:     req.tag
      };
   endmethod
endmodule

endpackage: AddrMapper
