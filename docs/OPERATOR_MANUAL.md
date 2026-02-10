# Pintle Operator and Developer Manual

This manual provides instructions for configuring, building, simulating, and verifying the Pintle CXL 3.1 coherent memory pool controller and switch fabric.

---

## 1. Prerequisites and Environment Setup

### 1.1 Toolchain Dependencies

To build and simulate Pintle, ensure the following tools are installed:

- **Bluespec Compiler (BSC)**: Version 2023.01 or later (tested with BSC 2026.07). The `bsc` binary must be in your `PATH` or configured via `BSC_BIN_DIR`.
- **C++ Compiler**: Clang++ (Apple LLVM 15.0+) or GCC (11.0+) with C++17 support.
- **Python**: Python 3.10 or later with standard library support.
- **Waveform Viewer** (Optional): GTKWave or Surfer for inspecting VCD trace files.

### 1.2 Environment Configuration

Export the path to your BSC installation if it is not located in `/usr/local/bin`:

```bash
export BSC_BIN_DIR="/path/to/bsc/bin"
export PATH="$BSC_BIN_DIR:$PATH"
```

---

## 2. Quickstart Build Commands

Pintle provides a comprehensive `Makefile` targeting simulation, RTL generation, and verification:

```bash
# Display help and target overview
make help

# Build all Bluespec testbench binaries
make bsv

# Run all Bluespec simulation testbenches
make test-bsv

# Build and execute the C++ DPI-C co-simulation stress test
make cosim

# Run all Python golden protocol verification test suites
make test-py

# Run the complete regression test suite
make test

# Synthesize synthesizable Verilog RTL for ASIC/FPGA flows
make verilog

# Remove all build artifacts, object files, and binaries
make clean
```

---

## 3. Running Bluesim Hardware Simulations

### 3.1 Individual Testbench Execution

You can run individual unit and integration testbenches directly from the command line:

```bash
# Run CRC-32C generator testbench
./bin/TbCrc32

# Run DDR5 bank queue and FR-FCFS scheduler testbench
./bin/TbDdr5Scheduler

# Run SECDED (72, 64) error correction testbench
./bin/TbEccSecDed

# Run streaming LZ4 decompressor testbench
./bin/TbLz4Decompress

# Run NIST AES-256-GCM testbench
./bin/TbAesGcmCore

# Run end-to-end multi-host memory pool integration testbench
./bin/TbPintleTop
```

### 3.2 Waveform Generation and Inspection

To generate cycle-accurate Value Change Dump (VCD) waveforms during Bluesim simulation, pass the `-V` runtime flag:

```bash
# Run simulation and dump waveforms to pintle_trace.vcd
./bin/TbPintleTop -V pintle_trace.vcd

# Open the trace in GTKWave
gtkwave pintle_trace.vcd
```

Key signal groups to inspect in GTKWave:
- `CLK` / `RST_N`: Core system clock and active-low synchronous reset.
- `unpacker_req_out`: Inbound CXL.mem M2S request flits.
- `coherence_engine`: MOESI directory state transitions and MSHR slot allocations.
- `ddr5_scheduler`: Bank queue depths, command bus arbitration, and timing counters.
- `packer_out`: Outbound CXL.mem S2M response flits with data payloads.

---

## 4. Multi-Agent C++ Co-Simulation

Pintle includes a high-throughput C++ co-simulation engine (`sim/`) that emulates 4 host CPUs driving concurrent, non-blocking CXL transactions against the memory pool:

```bash
# Compile and run the co-simulation stress suite (2,500 cycles default)
make cosim

# Run with custom cycle count
./bin/cosim_stress 10000
```

The co-simulation prints cycle-by-cycle transaction reports, monitors link-level CRC integrity, and asserts that no coherence invariants are violated across the shared memory space.

---

## 5. Python Reference Verification

The Python test suite provides comprehensive protocol conformance checking:

```bash
make test-py
```

Or run individual suites:

```bash
# Validate 256-byte flit packing and CRC-32C syndrome calculation
python3 tests/test_flit_codec.py

# Verify concurrent MOESI state transitions and MSHR conflict resolution
python3 tests/test_coherence_races.py

# Verify DDR5 JEDEC timing enforcers and sliding window constraints
python3 tests/test_ddr5_timings.py

# Verify SECDED single-bit correction and double-bit detection across all bit positions
python3 tests/test_ecc_injection.py

# Test LZ4 streaming hardware decompressor against compressed payloads
python3 tests/test_lz4_accelerator.py

# Validate AES-256-GCM cryptographic pipeline against NIST SP 800-38D vectors
python3 tests/test_aes_nist_vectors.py

# Test multi-host port-based routing and virtual output queuing
python3 tests/test_multi_host_pbr.py

# Run end-to-end multi-host memory pool integration scenario
python3 tests/test_end_to_end_pool.py
```

---

## 6. Real-Time Telemetry and Operational Tools

### 6.1 ANSI Terminal Telemetry Dashboard

Pintle provides an interactive, real-time terminal dashboard (`tools/telemetry_dashboard.py`) for live monitoring of controller performance:

```bash
# Run live dashboard for 10 seconds
python3 tools/telemetry_dashboard.py --duration 10

# Run in continuous monitoring mode
python3 tools/telemetry_dashboard.py --continuous
```

The dashboard renders:
- Link throughput (GB/s) and packet processing rate (MFlits/s).
- Per-bank queue occupancy across all 32 physical DDR5 banks.
- MSHR active hazard slots and conflict stall counters.
- SECDED single-bit error corrections and patrol scrubber progress.
- Core temperature and dynamic thermal governor throttle states.

### 6.2 PCIe/CXL Protocol Trace Replayer

To benchmark performance against real-world memory access distributions, use the trace replayer (`tools/cxl_trace_replay.py`):

```bash
# Replay 5,000 synthetic multi-host transactions
python3 tools/cxl_trace_replay.py --transactions 5000

# Replay an external trace file
python3 tools/cxl_trace_replay.py --trace traces/workload_sample.trace
```

The replayer outputs an ASCII latency histogram detailing $p_{50}$, $p_{90}$, $p_{99}$, and $p_{99.9}$ tail latencies.

---

## 7. Troubleshooting

### 7.1 BSC Stack Space Overflow
If building large top modules fails with `bsc: Stack space overflow`, ensure the BSC compiler runtime flag is provided:
```bash
bsc +RTS -K128M -RTS ...
```
This is configured automatically in the provided `Makefile`.

### 7.2 Missing Bluetcl in PATH
If simulation linking fails with `bluetcl: command not found`, add the BSC bin directory to your environment:
```bash
export PATH="$(dirname $(which bsc)):$PATH"
```

### 7.3 Verilog Compilation Warnings
When generating Verilog RTL with `make verilog`, BSC generates synthesizable Verilog files in `verilog_out/`. Ensure that your downstream synthesis tools (Vivado, Quartus, Yosys) include the BSC library Verilog models located in `$BLUESPECDIR/Verilog/`.
