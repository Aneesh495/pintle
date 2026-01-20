# Pintle CXL 3.1 Protocol Specification

This document provides the technical specification for the Compute Express Link (CXL) 3.1 protocol implementation in the Pintle coherent memory pool controller and fabric switch.

---

## 1. Protocol Architecture Overview

Pintle implements the CXL 3.1 specification for Type 3 pooling devices and multi-headed switches. The interface stack operates concurrently across three protocol sub-layers:

1. **CXL.io**: PCIe-based discovery, enumeration, configuration space access, and link training.
2. **CXL.cache**: Device-initiated coherent caching of host processor physical memory lines.
3. **CXL.mem**: Host-initiated coherent access to device-attached DDR5 memory pools.

```
+-----------------------------------------------------------------------+
|                             Host Processor                            |
|  +--------------------+  +--------------------+  +-----------------+  |
|  |     CXL.io Master  |  |   CXL.cache Agent  |  | CXL.mem Master  |  |
+--+----------+---------+--+---------+----------+--+--------+--------+--+
              |                      |                      |
              v                      v                      v
+-----------------------------------------------------------------------+
|                     Pintle CXL 3.1 Link Subsystem                     |
|  +-----------------------------------------------------------------+  |
|  |           256-Byte Standard Flit Packing and Framing            |  |
|  +-----------------------------------------------------------------+  |
|  |        CRC-32C Polynomial Generation and Syndrome Checking      |  |
|  +-----------------------------------------------------------------+  |
|  |           16-Entry Circular Retransmission Buffer               |  |
|  +-----------------------------------------------------------------+  |
|  |       Sliding-Window Credit-Based Virtual Channel Flow Control   |  |
+--+-----------------------------------------------------------------+--+
                                     |
                                     v
                        Physical Link (PCIe 6.0 PHY)
```

---

## 2. 256-Byte Flit Framing Structure

Pintle utilizes the standard 256-byte flit format introduced for CXL 3.1 64 GT/s PAM4 signaling. Every 256-byte flit contains four 64-byte chunks, subdivided into message header slots, payload data, and link integrity fields.

### 2.1 Flit Slot Layout

Each 256-byte standard flit is partitioned as follows:

| Byte Offset | Field Description | Width (Bytes) | Functionality |
| :--- | :--- | :--- | :--- |
| `0x00 - 0x0F` | Header Slot 0 | 16 | CXL.mem M2S Request or S2M Response header |
| `0x10 - 0x1F` | Header Slot 1 | 16 | CXL.cache D2H Request or H2D Response header |
| `0x20 - 0x27` | Credit Return & Ack | 8 | Flow control credit grant and sequence ACK/NAK |
| `0x28 - 0x2B` | Protocol Control | 4 | Flit sequence number, retry counter, error bits |
| `0x2C - 0x2F` | Reserved / FEC | 4 | Forward Error Correction framing metadata |
| `0x30 - 0x6F` | Data Chunk 0 | 64 | Cache line payload (64 bytes) |
| `0x70 - 0xAF` | Data Chunk 1 | 64 | Cache line payload (64 bytes) |
| `0xB0 - 0xEF` | Data Chunk 2 | 64 | Cache line payload (64 bytes) |
| `0xF0 - 0xFB` | Control / Meta | 12 | Sideband tags, poison indicators, bias hints |
| `0xFC - 0xFF` | Flit CRC-32C | 4 | Castagnoli CRC covering bytes 0x00 through 0xFB |

### 2.2 Flit Header Definitions

The M2S (Master to Subordinate) Request Header occupies 16 bytes (128 bits):

```
 127         120 119        112 111                                  64
+---------------+--------------+---------------------------------------+
|  Msg Class    |  Opcode      |            Target Address             |
|  (8 bits)     |  (8 bits)    |            [57:10] (48 bits)          |
+---------------+--------------+---------------------------------------+
 63       48 47          32 31    24 23             16 15              0
+-----------+--------------+--------+-----------------+-----------------+
|  Host ID  |   Tag / ID   | TC     | Memory Pool ID  | Metadata / Flags|
|  (16 bits)|   (16 bits)  | (8 b)  | (8 bits)        | (16 bits)       |
+-----------+--------------+--------+-----------------+-----------------+
```

Supported M2S Request Opcodes:
- `0x01`: `CXL_M2S_REQ_READ` (64-byte coherent read)
- `0x02`: `CXL_M2S_REQ_READ_NO_DATA` (Directory state probe without data transfer)
- `0x03`: `CXL_M2S_REQ_WRITE` (64-byte write with full cache line payload)
- `0x04`: `CXL_M2S_REQ_WRITE_PARTIAL` (Sub-cache-line write with byte enable mask)
- `0x05`: `CXL_M2S_REQ_FLUSH` (Cache line flush to persistent storage)
- `0x06`: `CXL_M2S_REQ_CLEAN_INVALIDATE` (Evict line and invalidate peer copies)

Supported S2M Response Opcodes:
- `0x01`: `CXL_S2M_RSP_DATA` (Read completion with 64-byte data payload)
- `0x02`: `CXL_S2M_RSP_DATA_SHARED` (Read completion in Shared directory state)
- `0x03`: `CXL_S2M_RSP_DATA_OWNED` (Read completion in Owned directory state)
- `0x04`: `CXL_S2M_RSP_WRITE_ACK` (Write posted acknowledgement)
- `0x05`: `CXL_S2M_RSP_CONFLICT` (MSHR address conflict detected, backoff required)
- `0x06`: `CXL_S2M_RSP_ERROR` (Uncorrectable ECC error or bus abort)

---

## 3. Link Integrity and CRC-32C

### 3.1 Mathematical Specification

Pintle protects all 256-byte flits against transmission bit errors using the standard CRC-32C (Castagnoli) generator polynomial:

$$G(x) = x^{32} + x^{28} + x^{27} + x^{26} + x^{25} + x^{23} + x^{22} + x^{20} + x^{19} + x^{18} + x^{14} + x^{13} + x^{11} + x^{10} + x^{9} + x^{8} + x^{6} + 1$$

In hexadecimal representation: `0x1EDC6F41`.

### 3.2 Parallel Hardware Implementation

The hardware module (`bsv/link/Crc32C.bsv`) executes 64-bit parallel remainder calculations per cycle. The generator matrix $M$ maps a 64-bit input vector $D$ and 32-bit current CRC state $C_{in}$ into the next state $C_{out}$:

$$C_{out} = M_{C} \cdot C_{in} \oplus M_{D} \cdot D$$

Properties of the implementation:
- Bit-reflection: Input bytes are processed LSB-first in accordance with IEEE 802.3 and CXL 3.1.
- Initial seed: `0xFFFFFFFF`.
- Final XOR: `0xFFFFFFFF`.
- Residual constant upon error-free reception: `0xDEBB20E3`.

---

## 4. Retransmission Protocol and Retry Buffer

### 4.1 Retry Buffer Architecture

To guarantee lossless transmission across PAM4 electrical channels, Pintle embeds a 16-entry circular retransmission buffer on each link port:

```
                  +----------------------------------------+
  Tx Flit Stream  | Slot 0: Flit Seq 0 (ACKed)             |
================> | Slot 1: Flit Seq 1 (In Flight)         | ----> PHY Tx
                  | Slot 2: Flit Seq 2 (In Flight)         |
                  | Slot 3: Flit Seq 3 (In Flight) <Tail   |
                  | Slot 4: Empty                          |
                  | ...                                    |
                  | Slot 15: Empty                         |
                  +----------------------------------------+
                       ^                      |
                       |                      v
                 Ack Reclaim             NAK Detected
                 (Advance Head)          (Rollback to Seq N)
```

### 4.2 State Machine Transitions

1. **Active Normal Mode**: Flits are assigned sequential 4-bit sequence numbers ($0 \dots 15$) and written into the circular buffer at index `tail_ptr`.
2. **ACK Reception**: When an incoming flit returns an ACK for sequence number $k$, all entries from `head_ptr` up to $k$ are released, freeing buffer slots for new outbound transmissions.
3. **NAK or CRC Error Reception**: If a NAK for sequence number $k$ is received, or if an incoming flit exhibits a CRC syndrome mismatch:
   - Outbound flit generation is halted immediately.
   - `tail_ptr` is rolled back to $k$.
   - The buffer retransmits flits starting from $k$ through the newest unacknowledged flit.
   - The retry counter in the PMU is incremented.

---

## 5. Flow Control Credit Architecture

Pintle operates a credit-based, receiver-managed flow control protocol across four independent Virtual Channels (VCs):

| Virtual Channel | Priority | Traffic Class | Description |
| :--- | :--- | :--- | :--- |
| `VC0` | Low | CXL.io | PCIe discovery, device configuration, CSR access |
| `VC1` | Medium | CXL.mem Read | Non-posted coherent read requests |
| `VC2` | High | CXL.mem Write | Posted write requests and write data payloads |
| `VC3` | Critical | CXL.cache / Snoop | Back-invalidation snoops and peer responses |

### 5.1 Flow Control Invariants

- **Forward Progress Guarantee**: Credits for `VC3` (Snoop/Back-Invalidation) are reserved with dedicated hardware queues to prevent deadlocks caused by circular dependencies between read requests and cache invalidations.
- **Credit Return Framing**: Credit returns are piggybacked onto every outbound flit in bytes `0x20 - 0x27`. If no payload flits are pending, dedicated control flits are generated when the local receiver buffer frees at least 4 slots.
- **Overrun Prevention**: A transmitter shall never dispatch a flit on $VC_n$ if the local credit register for $VC_n$ equals zero. Attempts to transmit without credits trigger an assert violation in simulation and drop the transaction in hardware while raising a PMU flow-control stall flag.
