/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/coherence/CacheDirectory.bsv
 * Description: Multi-banked set-associative directory cache tracking cache line
 *              coherence state (MESI/MOESI), sharer bitmasks, and device bias modes.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package CacheDirectory;

import Vector::*;
import RegFile::*;
import CxlTypes::*;
import CoherenceTypes::*;

typedef 64 NumDirSets;      // 64 Sets
typedef 4  NumDirWays;      // 4 Ways per set = 256 tracked lines
typedef Bit#(6) DirSetIdx;
typedef Bit#(2) DirWayIdx;

interface CacheDirectory;
   method Tuple2#(Bool, DirectoryEntry) lookup(Addr a);
   method Action update(Addr a, DirectoryEntry entry);
   method Action invalidateLine(Addr a);
   method Action setDeviceBias(Addr a, Bool is_dev_bias);
endinterface

(* synthesize *)
module mkCacheDirectory (CacheDirectory);
   // 4 Ways of Directory Entries, each way has 64 sets
   Vector#(4, RegFile#(DirSetIdx, DirectoryEntry)) dir_ways <- replicateM(mkRegFileFull());

   // Replacement counter per set (round-robin / pseudo-LRU)
   RegFile#(DirSetIdx, DirWayIdx) replace_ptr <- mkRegFileFull();

   function DirSetIdx getSetIdx(Addr a);
      return a[11:6];
   endfunction

   function Bit#(32) getTag(Addr a);
      return a[63:32];
   endfunction

   method Tuple2#(Bool, DirectoryEntry) lookup(Addr a);
      let set_idx = getSetIdx(a);
      let tag_val = getTag(a);

      Bool hit = False;
      DirectoryEntry hit_entry = unpack(0);

      for (Integer w = 0; w < 4; w = w + 1) begin
         let entry = dir_ways[w].sub(set_idx);
         if (entry.valid && entry.tag == tag_val) begin
            hit = True;
            hit_entry = entry;
         end
      end

      return tuple2(hit, hit_entry);
   endmethod

   method Action update(Addr a, DirectoryEntry entry);
      let set_idx = getSetIdx(a);
      let tag_val = getTag(a);

      // Check if entry already exists in one of the ways
      Bool found = False;
      DirWayIdx target_way = replace_ptr.sub(set_idx);

      for (Integer w = 0; w < 4; w = w + 1) begin
         let existing = dir_ways[w].sub(set_idx);
         if (existing.valid && existing.tag == tag_val) begin
            found = True;
            target_way = fromInteger(w);
         end
      end

      let new_entry = entry;
      new_entry.tag = tag_val;
      new_entry.valid = True;

      dir_ways[target_way].upd(set_idx, new_entry);

      if (!found) begin
         replace_ptr.upd(set_idx, target_way + 1);
      end
   endmethod

   method Action invalidateLine(Addr a);
      let set_idx = getSetIdx(a);
      let tag_val = getTag(a);

      for (Integer w = 0; w < 4; w = w + 1) begin
         let existing = dir_ways[w].sub(set_idx);
         if (existing.valid && existing.tag == tag_val) begin
            let inv_entry = existing;
            inv_entry.valid = False;
            inv_entry.state = COH_INVALID;
            inv_entry.sharers = 0;
            dir_ways[w].upd(set_idx, inv_entry);
         end
      end
   endmethod

   method Action setDeviceBias(Addr a, Bool is_dev_bias);
      let set_idx = getSetIdx(a);
      let tag_val = getTag(a);

      for (Integer w = 0; w < 4; w = w + 1) begin
         let existing = dir_ways[w].sub(set_idx);
         if (existing.valid && existing.tag == tag_val) begin
            let upd_entry = existing;
            upd_entry.is_device_bias = is_dev_bias;
            dir_ways[w].upd(set_idx, upd_entry);
         end
      end
   endmethod
endmodule

endpackage: CacheDirectory
