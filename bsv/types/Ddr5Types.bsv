/*
 * PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
 * File: bsv/types/Ddr5Types.bsv
 * Description: JEDEC DDR5 SDRAM commands, timing parameters, and internal
 *              bank controller structures.
 *
 * Author: Aneesh Krishna Parthasarathy
 * License: ISC License
 */

package Ddr5Types;



// ----------------------------------------------------------------------
// DDR5 SDRAM Architecture Dimensions
// ----------------------------------------------------------------------

typedef 4  Ddr5NumChannels;
typedef 2  Ddr5NumRanks;
typedef 4  Ddr5NumBankGroups;
typedef 8  Ddr5NumBanksPerGroup;
typedef 32 Ddr5TotalBanksPerChannel; // 4 groups * 8 banks
typedef 18 Ddr5RowBits;
typedef 10 Ddr5ColBits;

typedef Bit#(2)  ChannelIdx;
typedef Bit#(1)  RankIdx;
typedef Bit#(2)  BankGroupIdx;
typedef Bit#(3)  BankIdx;
typedef Bit#(5)  GlobalBankIdx; // [4:3]=group, [2:0]=bank
typedef Bit#(18) RowAddr;
typedef Bit#(10) ColAddr;

function GlobalBankIdx toGlobalBank(BankGroupIdx bg, BankIdx b);
   return {bg, b};
endfunction

// ----------------------------------------------------------------------
// JEDEC DDR5 Command Encodings
// ----------------------------------------------------------------------

typedef enum {
   DDR5_CMD_DES,     // Device Deselect / NOP
   DDR5_CMD_ACT,     // Activate (Row Open)
   DDR5_CMD_PRE,     // Precharge Individual Bank
   DDR5_CMD_PREA,    // Precharge All Banks in Channel
   DDR5_CMD_READ,    // Column Read Burst
   DDR5_CMD_WRITE,   // Column Write Burst
   DDR5_CMD_REF,     // Auto-Refresh
   DDR5_CMD_RFM,     // Refresh Management
   DDR5_CMD_ZQCS     // ZQ Impedance Calibration
} Ddr5Cmd deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// Per-Bank State Machine
// ----------------------------------------------------------------------

typedef enum {
   BANK_IDLE,        // Precharged, ready for ACT command
   BANK_ACTIVATING,  // Row opening in progress (waiting tRCD)
   BANK_ACTIVE,      // Row open, ready for READ/WRITE commands
   BANK_PRECHARGING  // Bank closing in progress (waiting tRP)
} BankState deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------------
// DDR5 AC Timing Constraints (Configurable clock cycle thresholds)
// ----------------------------------------------------------------------

typedef struct {
   UInt#(8) t_rcd;    // RAS to CAS delay (Active to Read/Write)
   UInt#(8) t_rp;     // Row Precharge time (Precharge to Active)
   UInt#(8) t_ras;    // Row Active time (Active to Precharge)
   UInt#(8) t_wr;     // Write Recovery time (Write to Precharge)
   UInt#(8) t_cl;     // CAS Read Latency
   UInt#(8) t_ccd_s;  // Column-to-Column short (different bank groups)
   UInt#(8) t_ccd_l;  // Column-to-Column long (same bank group)
   UInt#(8) t_wtr_s;  // Write-to-Read short
   UInt#(8) t_wtr_l;  // Write-to-Read long
   UInt#(16) t_refi;  // Refresh Interval (typically ~3.9us / 7.8us)
   UInt#(8) t_rfc;    // Refresh Cycle time
} Ddr5TimingConfig deriving (Bits, Eq, FShow);

function Ddr5TimingConfig defaultDdr5Timings();
   return Ddr5TimingConfig {
      t_rcd:   14,
      t_rp:    14,
      t_ras:   32,
      t_wr:    30,
      t_cl:    14,
      t_ccd_s: 4,
      t_ccd_l: 8,
      t_wtr_s: 4,
      t_wtr_l: 10,
      t_refi:  1560,
      t_rfc:   120
   };
endfunction

// ----------------------------------------------------------------------
// DDR5 Physical Request and Response Packets
// ----------------------------------------------------------------------

typedef struct {
   ChannelIdx   channel;
   RankIdx      rank;
   BankGroupIdx bank_group;
   BankIdx      bank;
   RowAddr      row;
   ColAddr      col;
   Bool         is_write;
   Bit#(512)    write_data;
   Bit#(64)     byte_en;
   Bit#(12)     req_id;
} Ddr5MemRequest deriving (Bits, Eq, FShow);

typedef struct {
   ChannelIdx channel;
   Bit#(12)   req_id;
   Bit#(512)  read_data;
   Bool       ecc_corrected;
   Bool       ecc_fatal_error;
} Ddr5MemResponse deriving (Bits, Eq, FShow);

endpackage: Ddr5Types
