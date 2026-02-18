# ==============================================================================
# PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller
# Master Build, Simulation, and Verification Automation
# ==============================================================================

BSC ?= $(shell which bsc 2>/dev/null || echo /Users/aneeshkrishna/tools/bsc-2026.07.1-macos-26/bin/bsc)
BSC_BIN_DIR = $(dir $(BSC))
export PATH := $(BSC_BIN_DIR):$(PATH)
PYTHON ?= python3
CXX ?= clang++

BUILD_DIR ?= build
SIM_DIR ?= sim_build
BIN_DIR ?= bin
VLOG_DIR ?= verilog_out

BSV_SRC_DIRS = bsv/types:bsv/link:bsv/fabric:bsv/coherence:bsv/mem_ctrl:bsv/accel:bsv/mgmt:bsv/top:tb
BSC_PATH_FLAGS = -p +:$(BSV_SRC_DIRS)
BSC_RTS_FLAGS = +RTS -K128M -RTS
BSC_SIM_FLAGS = $(BSC_RTS_FLAGS) -sim -u -aggressive-conditions -check-assert -Xc++ -O1 -bdir $(BUILD_DIR) -simdir $(SIM_DIR)
BSC_VLOG_FLAGS = $(BSC_RTS_FLAGS) -verilog -u -aggressive-conditions -bdir $(BUILD_DIR) -vdir $(VLOG_DIR)

TESTBENCHES = \
	TbCrc32 \
	TbFlitPacker \
	TbCreditFlow \
	TbCrossbar \
	TbCacheDirectory \
	TbBackInvalidator \
	TbConflictTable \
	TbDdr5Scheduler \
	TbEccSecDed \
	TbLz4Decompress \
	TbAesGcmCore \
	TbPmuCounters \
	TbPintleTop

.PHONY: all help dirs test test-bsv test-py lint clean sim verilog stats

all: dirs test-bsv stats

help:
	@echo "PINTLE: Compute Express Link (CXL 3.1) Coherent Memory Pool Controller"
	@echo "Targets:"
	@echo "  all        : Run all unit and integration simulations"
	@echo "  test-bsv   : Compile and execute all Bluesim testbenches"
	@echo "  test-py    : Run Python protocol verification test suites"
	@echo "  test       : Run both BSV and Python test suites"
	@echo "  verilog    : Synthesize BSV modules into synthesizable Verilog"
	@echo "  lint       : Check dash compliance and style"
	@echo "  stats      : Print line count and metrics breakdown"
	@echo "  clean      : Remove all generated simulation and build artifacts"

dirs:
	@mkdir -p $(BUILD_DIR) $(SIM_DIR) $(BIN_DIR) $(VLOG_DIR)

$(BIN_DIR)/%: tb/%.bsv dirs
	@echo "[BSC-SIM] Compiling $<..."
	@$(BSC) $(BSC_PATH_FLAGS) $(BSC_SIM_FLAGS) -g mk$* $<
	@echo "[BSC-LINK] Linking $@..."
	@$(BSC) $(BSC_PATH_FLAGS) $(BSC_SIM_FLAGS) -e mk$* -o $@

test-bsv: dirs $(addprefix $(BIN_DIR)/, $(TESTBENCHES))
	@echo "======================================================================"
	@echo "Running Bluesim Hardware Verification Suite"
	@echo "======================================================================"
	@for tb in $(TESTBENCHES); do \
		echo "--> Executing testbench: $$tb"; \
		PATH="$(BSC_BIN_DIR):$$PATH" $(BIN_DIR)/$$tb || exit 1; \
	done
	@echo "All Bluesim testbenches PASSED successfully."

test-py:
	@echo "======================================================================"
	@echo "Running Python Protocol & Verification Test Suite"
	@echo "======================================================================"
	@for test in tests/test_*.py; do \
		echo "--> Executing suite: $$test"; \
		$(PYTHON) $$test || exit 1; \
	done
	@echo "All Python verification test suites PASSED."

test: test-bsv test-py

verilog: dirs
	@echo "======================================================================"
	@echo "Generating Synthesizable Verilog via BSC"
	@echo "======================================================================"
	@$(BSC) $(BSC_PATH_FLAGS) $(BSC_VLOG_FLAGS) -g mkPintleMemoryPool bsv/top/PintleMemoryPool.bsv
	@$(BSC) $(BSC_PATH_FLAGS) $(BSC_VLOG_FLAGS) -g mkPintleSwitchTop bsv/top/PintleSwitchTop.bsv
	@echo "Verilog generation complete in $(VLOG_DIR)/"

lint:
	@$(PYTHON) tools/check_no_em_dash.py

stats:
	@$(PYTHON) tools/line_count.py

clean:
	@rm -rf $(BUILD_DIR) $(SIM_DIR) $(BIN_DIR) $(VLOG_DIR)
	@rm -rf *.ba *.bo *.bi *.h *.o *.so *.dylib *.vcd
	@rm -rf __pycache__ tests/__pycache__ tools/__pycache__ sim/__pycache__
	@echo "Cleaned build artifacts."
