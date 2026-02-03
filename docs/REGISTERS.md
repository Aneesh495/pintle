# Pintle Register Map Specification

This document details the memory-mapped Control and Status Register (CSR) space accessible via the 32-bit AXI4-Lite slave interface in Pintle.

---

## 1. Address Space Layout

The Pintle CSR bank (`bsv/mgmt/CxlCsrBank.bsv`) occupies a 4KB address block partitioned into functional sub-regions:

| Base Offset | Range | Functional Subsystem |
| :--- | :--- | :--- |
| `0x000` | `0x03F` | Device Identification and Capability Registers |
| `0x040` | `0x07F` | CXL 3.1 DVSEC (Designated Vendor-Specific Extended Capability) |
| `0x080` | `0x0BF` | Coherence and Bias Engine Control Registers |
| `0x0C0` | `0x0FF` | DDR5 Memory Controller Configuration and Timings |
| `0x100` | `0x13F` | Memory Patrol Scrubber Control and Status |
| `0x140` | `0x17F` | Hardware Accelerators (LZ4, AES-GCM, SIMD Filter) Control |
| `0x180` | `0x1BF` | Thermal Governor and Fan Speed Telemetry |
| `0x200` | `0x27F` | Performance Monitoring Unit (PMU) 64-bit Hardware Counters |

---

## 2. Register Definitions

### 2.1 Device Identification and Status

#### `0x000` : `DEV_ID_REG` (Device Identification Register, Read Only)
- Bits `[31:16]`: Vendor ID (`0x1E3C` = Pintle Open Hardware)
- Bits `[15:0]`: Device ID (`0xC310` = CXL 3.1 Memory Pool Controller)

#### `0x004` : `DEV_REV_REG` (Revision and Status Register, Read Only)
- Bits `[31:24]`: Major Revision (`0x01`)
- Bits `[23:16]`: Minor Revision (`0x00`)
- Bits `[15:8]`: Stepping (`0x01`)
- Bits `[7:0]`: Hardware Status flags (bit 0 = Link Up, bit 1 = DDR5 Ready, bit 2 = Coherence Active)

#### `0x008` : `DEV_CTRL_REG` (Master Device Control Register, Read/Write)
- Bit `[0]`: Subsystem Soft Reset (self-clearing)
- Bit `[1]`: Global Interrupt Enable
- Bit `[2]`: Performance Monitoring Unit Enable
- Bit `[3]`: Near-Memory Acceleration Subsystem Enable
- Bits `[31:4]`: Reserved

---

### 2.2 CXL 3.1 DVSEC Registers

#### `0x040` : `CXL_DVSEC_HDR1_REG` (DVSEC Header 1, Read Only)
- Bits `[31:16]`: DVSEC Length (`0x003C` = 60 bytes)
- Bits `[15:4]`: DVSEC Revision (`0x001`)
- Bits `[3:0]`: DVSEC ID (`0x0` = PCIe CXL Device Capability)

#### `0x044` : `CXL_DVSEC_CAP_REG` (CXL Device Capability, Read Only)
- Bit `[0]`: CXL.io Capable (`1'b1`)
- Bit `[1]`: CXL.cache Capable (`1'b1`)
- Bit `[2]`: CXL.mem Capable (`1'b1`)
- Bit `[3]`: Mem HDM Count (`1'b1` = 1 Host-Managed Device Memory range)
- Bit `[4]`: Multi-Head Device Capable (`1'b1` = 4 Host Ports supported)
- Bits `[31:5]`: Reserved

#### `0x048` : `CXL_DVSEC_CTRL_REG` (CXL Device Control, Read/Write)
- Bit `[0]`: CXL.io Enable (`1'b1`)
- Bit `[1]`: CXL.cache Enable
- Bit `[2]`: CXL.mem Enable
- Bits `[31:3]`: Reserved

---

### 2.3 Memory Controller and Scrubber Registers

#### `0x0C0` : `DDR5_CFG_REG` (DDR5 Channel Configuration, Read/Write)
- Bits `[1:0]`: Active Channel Mask (bit 0 = Channel A, bit 1 = Channel B)
- Bits `[3:2]`: Subchannel Interleave Mode (`00` = XOR Hash, `01` = Linear)
- Bits `[7:4]`: Command Queue High-Watermark Throttle Threshold (default 6)
- Bits `[31:8]`: Reserved

#### `0x100` : `SCRUB_CTRL_REG` (Patrol Scrubber Control, Read/Write)
- Bit `[0]`: Scrubber Enable
- Bit `[1]`: Scrub Single-Error Writeback Inhibit (Diagnostic Mode)
- Bit `[2]`: Scrubber Reset Address Pointer
- Bits `[31:3]`: Reserved

#### `0x104` : `SCRUB_INTERVAL_REG` (Scrubber Cycle Interval, Read/Write)
- Bits `[31:0]`: Clock cycle interval between consecutive patrol reads (default `0x0000_03E8` = 1000 cycles)

#### `0x108` : `SCRUB_CURR_ADDR_REG` (Scrubber Current Address, Read Only)
- Bits `[31:0]`: Current 64-byte aligned DRAM physical address under inspection

---

### 2.4 Performance Monitoring Unit (PMU) Counters

Each PMU metric is recorded in a 64-bit saturating counter exposed across two 32-bit registers (`_LO` and `_HI`). Counters are reset by writing `1` to `PMU_RST_REG` (`0x200`).

| Register Offset | Counter Name | Description |
| :--- | :--- | :--- |
| `0x204` / `0x208` | `PMU_CYCLE_COUNT` | Cumulative controller core clock cycles |
| `0x20C` / `0x210` | `PMU_READ_COUNT` | Total completed CXL.mem read requests |
| `0x214` / `0x218` | `PMU_WRITE_COUNT` | Total completed CXL.mem write requests |
| `0x21C` / `0x220` | `PMU_FLIT_RETRY` | Total flit retransmissions triggered by CRC/NAK |
| `0x224` / `0x228` | `PMU_CRC_ERROR` | Total received flits with CRC-32C syndrome errors |
| `0x22C` / `0x230` | `PMU_ECC_CORR` | Total DDR5 SECDED single-bit errors corrected |
| `0x234` / `0x238` | `PMU_ECC_FATAL` | Total DDR5 SECDED multi-bit uncorrectable errors |
| `0x23C` / `0x240` | `PMU_CONFLICT_STALL` | Total cycles stalled due to MSHR address hazards |
| `0x244` / `0x248` | `PMU_THERMAL_THROTTLE` | Total cycles running under thermal throttle backoff |
| `0x24C` / `0x250` | `PMU_ACCEL_OPS` | Total operations executed in near-memory accelerators |

---

### 2.5 Thermal Governor Registers

#### `0x180` : `THERM_STATUS_REG` (Thermal Status, Read Only)
- Bits `[11:0]`: Current on-die temperature sensor reading in steps of $0.1^\circ\text{C}$
- Bit `[16]`: Critical Thermal Alarm Active
- Bit `[17]`: Warning Thermal Alarm Active
- Bits `[31:18]`: Reserved

#### `0x184` : `THERM_THRESH_REG` (Thermal Trip Points, Read/Write)
- Bits `[11:0]`: Warning Threshold Temperature (default `85.0 C`)
- Bits `[23:12]`: Critical Shutdown Temperature (default `105.0 C`)
- Bits `[31:24]`: Fan PWM Minimum Duty Cycle (0 to 255)
