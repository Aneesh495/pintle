# Pintle Verification Plan and Methodology

This document outlines the multi-tiered verification methodology employed across the Pintle CXL 3.1 memory pool controller and switch fabric.

---

## 1. Verification Strategy Overview

Pintle utilizes a four-tier verification architecture combining cycle-accurate hardware simulation, high-speed C++ co-simulation, and exhaustive Python protocol reference models:

```
+--------------------------------------------------------------------------+
|                     Tier 1: Bluespec Unit Testbenches                    |
|  - TbCrc32             - TbFlitPacker          - TbCreditFlow            |
|  - TbCrossbar          - TbCacheDirectory      - TbBackInvalidator       |
|  - TbConflictTable     - TbDdr5Scheduler       - TbEccSecDed             |
|  - TbLz4Decompress     - TbAesGcmCore          - TbPmuCounters           |
+--------------------------------------------------------------------------+
                                    |
                                    v
+--------------------------------------------------------------------------+
|                 Tier 2: Multi-Host Integration Testbench                 |
|  - TbPintleTop (Multi-port fabric, concurrent host read/write, snooping) |
+--------------------------------------------------------------------------+
                                    |
                                    v
+--------------------------------------------------------------------------+
|              Tier 3: C++ DPI-C Co-Simulation Stress Engine               |
|  - 4 Independent Virtual Host Agents                                     |
|  - Randomized Non-Blocking Traffic Generator                             |
|  - Hardware Protocol Monitors & Coherence Invariant Checker              |
+--------------------------------------------------------------------------+
                                    |
                                    v
+--------------------------------------------------------------------------+
|            Tier 4: Python Formal and Golden Reference Suites             |
|  - test_flit_codec.py          - test_coherence_races.py                 |
|  - test_ddr5_timings.py        - test_ecc_injection.py                  |
|  - test_lz4_accelerator.py     - test_aes_nist_vectors.py                |
|  - test_multi_host_pbr.py      - test_end_to_end_pool.py                 |
+--------------------------------------------------------------------------+
```

---

## 2. Test Execution Matrix

### 2.1 Bluesim Hardware Unit and Integration Suites

| Test Target | Testbench Binary | Description | Verification Checks |
| :--- | :--- | :--- | :--- |
| `bsv/link/Crc32C.bsv` | `bin/TbCrc32` | CRC-32C Castagnoli generator | Known IEEE vectors, error bit detection |
| `bsv/link/FlitPacker.bsv` | `bin/TbFlitPacker` | 256B Flit pack / unpack | Bidirectional loopback, header integrity |
| `bsv/link/CreditFlowCtrl.bsv` | `bin/TbCreditFlow` | Credit-based flow control | Dynamic credit allocation, stall on 0 credits |
| `bsv/fabric/CrossbarSwitch.bsv` | `bin/TbCrossbar` | 4x4 Virtual Output Queue switch | Contention arbitration, lossless routing |
| `bsv/coherence/CacheDirectory.bsv` | `bin/TbCacheDirectory` | Full-map MOESI directory | State transitions, sharer tracking, ownership |
| `bsv/coherence/BackInvalidator.bsv` | `bin/TbBackInvalidator` | Hardware snoop broadcaster | Multi-host snoop generation, ack collection |
| `bsv/coherence/ConflictTable.bsv` | `bin/TbConflictTable` | 16-entry MSHR CAM hazard table | Hazard allocation, RAR hit merge, WAW stall |
| `bsv/mem_ctrl/Ddr5Scheduler.bsv` | `bin/TbDdr5Scheduler` | FR-FCFS DDR5 bank scheduler | Page hit prioritization, write turnaround |
| `bsv/mem_ctrl/EccSecDed.bsv` | `bin/TbEccSecDed` | (72, 64) Hsiao SECDED ECC | Clean data, single-bit fix, double-bit alarm |
| `bsv/accel/Lz4Decompress.bsv` | `bin/TbLz4Decompress` | Near-memory LZ4 streaming engine | Token parsing, run-length match expansion |
| `bsv/accel/AesGcmCore.bsv` | `bin/TbAesGcmCore` | AES-256-GCM CXL IDE cryptographic core | NIST SP 800-38D test vectors, GHASH |
| `bsv/mgmt/PmuCounters.bsv` | `bin/TbPmuCounters` | Performance monitor counters | Read/write tally, overflow saturation |
| `bsv/top/PintleMemoryPool.bsv` | `bin/TbPintleTop` | End-to-end multi-host memory pool | Multi-host concurrent read, write, and snoops |

---

## 3. Fault Injection Testing

To rigorously stress robustness against hardware defects and transmission errors, the verification suite executes targeted fault injection:

### 3.1 ECC Single and Double Bit Inversion
- **Single-Bit Inversion**: For every bit position $i \in [0, 63]$ of data and $k \in [0, 7]$ of parity, a single bit is flipped before feeding into `mkEccDecoder`. The suite verifies that:
  1. The corrected output data bitwise matches the original golden data word.
  2. The single-error flag is asserted.
  3. The double-error flag remains deasserted.
- **Double-Bit Inversion**: For all pairs $(i, j)$ with $i \ne j$, two bits are simultaneously inverted. The suite verifies that:
  1. The double-error alarm is asserted.
  2. The transaction is tagged as poisoned.
  3. The hardware refuses to commit corrupt data to the host.

### 3.2 CRC Corruption and Retransmission
Flits transmitted through the link layer are subjected to randomized bit flips. The test asserts that:
1. The receiving link layer flags a syndrome error.
2. A NAK flit is transmitted back to the transmitter.
3. The circular retry buffer rolls back its tail pointer and successfully replays the uncorrupted packet.

### 3.3 High-Contention MSHR Line Races
Four concurrent host agents issue simultaneous write-after-read and write-after-write transactions to the same 64-byte address line. The suite verifies that:
1. Zero data corruption or silent loss occurs.
2. Transactions are serialized in strict temporal order.
3. No protocol deadlock occurs across $10^6$ simulation cycles.

---

## 4. Golden Reference Verification

The Python test suite (`tests/`) serves as an independent executable golden reference:
- `test_flit_codec.py`: Validates flit slot serialization, endianness, and Castagnoli CRC against RFC 3720 / CXL 3.1 standards.
- `test_coherence_races.py`: Simulates concurrent Petri-net state spaces of MOESI state transitions, verifying safety and liveness invariants.
- `test_ddr5_timings.py`: Validates exact cycle count constraints for $t_{RCD}$, $t_{RP}$, $t_{RAS}$, $t_{RRD}$, and the four-activate sliding window.
- `test_lz4_accelerator.py`: Compresses arbitrary synthetic and text datasets and verifies decompression byte-for-byte against the hardware simulation output.
- `test_aes_nist_vectors.py`: Validates encryption round transformations and GHASH polynomial authentication against NIST SP 800-38D official test vectors.
