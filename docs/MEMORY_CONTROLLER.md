# Pintle DDR5 Memory Controller Subsystem

This document specifies the microarchitecture of the Pintle high-performance DDR5-6400 memory controller, addressing address mapping, bank scheduling, JEDEC timing enforcement, SECDED error correction, and background patrol scrubbing.

---

## 1. Memory Architecture Overview

Pintle interfaces to high-density DDR5 SDRAM modules configured as two independent channels, each partitioned into two 32-bit subchannels (Channels A0, A1, B0, B1). Each subchannel controls 8 bank groups with 4 banks per group, yielding 32 physical banks per subchannel (128 banks total across the controller).

```
                      Physical Address [57:0]
                                 |
                                 v
             +---------------------------------------+
             |    XOR Pseudo-Random Address Mapper   |
             +---------------------------------------+
                |           |           |         |
                v           v           v         v
             Channel    Bank Group     Bank      Row / Col
             [1:0]        [2:0]       [1:0]     [17:0] / [9:0]
                |
                +-----------------------+
                |                       |
                v                       v
      +-------------------+   +-------------------+
      | Subchannel 0 Ddr5 |   | Subchannel 1 Ddr5 |
      | 32 Bank Queues    |   | 32 Bank Queues    |
      +-------------------+   +-------------------+
                |                       |
                v                       v
      +-------------------+   +-------------------+
      | FR-FCFS Scheduler |   | FR-FCFS Scheduler |
      +-------------------+   +-------------------+
                |                       |
                v                       v
      +-------------------+   +-------------------+
      | Timing Enforcers  |   | Timing Enforcers  |
      +-------------------+   +-------------------+
                |                       |
                v                       v
      +-------------------+   +-------------------+
      | (72,64) SECDED    |   | (72,64) SECDED    |
      +-------------------+   +-------------------+
                |                       |
                v                       v
            DDR5 DFI                DDR5 DFI
```

---

## 2. XOR Pseudo-Random Address Interleaving

Standard linear address decoding maps sequential cache lines to contiguous rows or banks. In multi-threaded and matrix transposition workloads, power-of-two access strides frequently collapse all transactions onto a single bank, degrading throughput by up to 85%.

Pintle prevents bank hotspotting using XOR hash interleaving (`bsv/mem_ctrl/AddrMapper.bsv`):

$$\text{BankGroup} = \text{Addr}[8:6] \oplus \text{Addr}[14:12] \oplus \text{Addr}[20:18]$$
$$\text{Bank} = \text{Addr}[10:9] \oplus \text{Addr}[16:15] \oplus \text{Addr}[22:21]$$
$$\text{Channel} = \text{Addr}[6] \oplus \text{Addr}[11]$$

This hashing distributes sequential, stride-64, stride-1024, and stride-4096 memory accesses across all 32 banks uniformly.

---

## 3. FR-FCFS Bank Scheduling

Each of the 32 physical banks features a dedicated 8-entry command queue (`bsv/mem_ctrl/BankQueue.bsv`). Command selection uses First-Ready First-Come-First-Served (FR-FCFS) arbitration (`bsv/mem_ctrl/Ddr5Scheduler.bsv`):

1. **Page Hit Priority**: Requests targeting the currently open row buffer within a bank are prioritized over requests requiring a row precharge (`PRECHARGE`) and activation (`ACTIVATE`).
2. **Oldest-First Secondary Arbitration**: If multiple banks have page hits ready, the request with the earliest arrival timestamp is selected.
3. **Read-Over-Write Turnaround Minimization**: The scheduler services bursts of read requests before executing a bus turnaround to flush pending write commands, amortizing the $t_{WTR}$ and $t_{RTW}$ bus turnaround penalties.

---

## 4. JEDEC Timing Enforcement

SDRAM physics require strict compliance with minimum recovery and precharge intervals. Pintle implements cycle-accurate hardware countdown timers (`bsv/mem_ctrl/TimingEnforcer.bsv`) configured for DDR5-6400 (clock period $t_{CK} = 0.3125\text{ ns}$):

| Parameter | JEDEC Description | Min Cycles ($t_{CK}$) | Hardware Enforcement Rule |
| :--- | :--- | :--- | :--- |
| $t_{RCD}$ | Row-to-Column Delay | 14 | Min delay between ACTIVATE and READ/WRITE |
| $t_{RP}$ | Row Precharge Time | 14 | Min delay between PRECHARGE and ACTIVATE |
| $t_{CAS}$ | Column Address Strobe Latency | 14 | Read command to data burst launch delay |
| $t_{RAS}$ | Row Active Time | 32 | Min time a row must remain open after ACTIVATE |
| $t_{RC}$ | Row Cycle Time | 46 | Min interval between successive ACTIVATE to same bank |
| $t_{RRD\_L}$ | Row Active to Row Active (same BG) | 8 | Min interval between ACTIVATE to same Bank Group |
| $t_{RRD\_S}$ | Row Active to Row Active (diff BG) | 4 | Min interval between ACTIVATE to diff Bank Group |
| $t_{FAW}$ | Four-Activate Window | 32 | Sliding window limiting max 4 activations |
| $t_{WR}$ | Write Recovery Time | 30 | Min delay after write burst before PRECHARGE |
| $t_{WTR\_L}$| Write-to-Read Delay (same BG) | 16 | Bus turnaround delay after write burst |
| $t_{RFC}$ | Refresh Cycle Time | 140 | Duration of auto-refresh operation |

### 4.1 Four-Activate Window ($t_{FAW}$) Slider

The $t_{FAW}$ enforcer tracks a 4-deep shift register storing the cycle timestamps of the last four `ACTIVATE` commands. An `ACTIVATE` command is legally permitted if and only if:

$$\text{CurrentCycle} - \text{Timestamp}[0] \ge t_{FAW}$$

---

## 5. SECDED (72, 64) Error Correction Code

To protect physical DRAM against alpha-particle radiation and soft errors, Pintle implements a (72, 64) Single-Error-Correction Double-Error-Detection (SECDED) Hsiao parity check matrix (`bsv/mem_ctrl/EccSecDed.bsv`).

### 5.1 Parity Generation

For a 64-bit data word $D[63:0]$, 8 parity bits $P[7:0]$ are generated using minimum-weight odd parity rows:

$$P[k] = \bigoplus_{i=0}^{63} (H[k][i] \cdot D[i])$$

Parity bit $P[7]$ acts as the overall parity accumulator over all data and parity bits to distinguish single-bit errors from double-bit errors.

### 5.2 Syndrome Decoding and Correction

Upon reading from DDR5, the hardware computes an 8-bit syndrome $S[7:0]$:

$$S[k] = P_{read}[k] \oplus \bigoplus_{i=0}^{63} (H[k][i] \cdot D_{read}[i])$$

- **$S = 0$**: Zero errors detected. Data is clean.
- **$S \ne 0$ and $S[7] = 1$**: Single-bit error detected. The lower 7 bits $S[6:0]$ decode the exact bit position in $D$ or $P$. The failing bit is inverted in hardware before forwarding to the host. The corrected error counter is incremented in PMU CSRs.
- **$S \ne 0$ and $S[7] = 0$**: Double-bit or uncorrectable error detected. The transaction is marked poisoned, and an uncorrectable ECC interrupt is signaled.

---

## 6. Background Patrol Memory Scrubber

Over extended operating cycles, single-bit soft errors can accumulate into uncorrectable double-bit errors if uncorrected. Pintle incorporates an autonomous patrol scrubber (`bsv/mem_ctrl/MemScrubber.bsv`).

### 6.1 Scrubbing Algorithm

1. **Patrol Counter**: An internal cycle counter triggers every $N$ cycles (configured via CSR `SCRUB_INTERVAL_REG`, default 1000 cycles).
2. **Read-Verify-Writeback Cycle**:
   - The scrubber issues a read command to current physical address `scrub_addr`.
   - The data is checked through the SECDED engine.
   - If a single-bit error is detected, the corrected data word is immediately written back to DDR5 at `scrub_addr`.
   - The scrubber logs the failing physical address and syndrome in the Scrubber Defect Log CSR.
3. **Address Advance**: `scrub_addr` is incremented by 64 bytes, wrapping around at the end of the physical address space.
4. **Bandwidth Throttling**: If host traffic exceeds 90% link saturation, the scrubber pauses automatically to prioritize host memory latency.
