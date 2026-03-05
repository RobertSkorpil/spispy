# Makefile for running VHDL testbenches with nvc
# Wave (FST) generation is enabled by default.

NVC      ?= nvc
WORKDIR  := work
NVCFLAGS ?= --std=93

# Source files
SPISPY_SRC   := spispy.vhdl
SPISPY_TB    := spispy_tb.vhdl

BUFCTRL_SRC  := bufctrl.vhdl
BUFCTRL_TB   := bufctrl_tb.vhdl

# Wave output files
SPISPY_WAVE  := spispy_tb.fst
BUFCTRL_WAVE := bufctrl_tb.fst

# ---------------------------------------------------------------
# Default: run all testbenches
# ---------------------------------------------------------------
.PHONY: all clean spispy bufctrl waves

all: spispy bufctrl

# ---------------------------------------------------------------
# spispy testbench
# ---------------------------------------------------------------
spispy: $(SPISPY_WAVE)
	@echo "=== spispy_tb complete — waveform: $(SPISPY_WAVE) ==="

$(SPISPY_WAVE): $(SPISPY_SRC) $(SPISPY_TB)
	$(NVC) $(NVCFLAGS) -a $(SPISPY_SRC) $(SPISPY_TB)
	$(NVC) $(NVCFLAGS) -e spispy_tb
	$(NVC) $(NVCFLAGS) -r spispy_tb --wave=$(SPISPY_WAVE)

# ---------------------------------------------------------------
# bufctrl testbench
# ---------------------------------------------------------------
bufctrl: $(BUFCTRL_WAVE)
	@echo "=== bufctrl_tb complete — waveform: $(BUFCTRL_WAVE) ==="

$(BUFCTRL_WAVE): $(BUFCTRL_SRC) $(BUFCTRL_TB)
	$(NVC) $(NVCFLAGS) -a $(BUFCTRL_SRC) $(BUFCTRL_TB)
	$(NVC) $(NVCFLAGS) -e bufctrl_tb
	$(NVC) $(NVCFLAGS) -r bufctrl_tb --wave=$(BUFCTRL_WAVE)

# ---------------------------------------------------------------
# Open waveforms in GTKWave
# ---------------------------------------------------------------
waves: all
	gtkwave $(SPISPY_WAVE) &
	gtkwave $(BUFCTRL_WAVE) &

# ---------------------------------------------------------------
# Clean build artifacts
# ---------------------------------------------------------------
clean:
	rm -rf $(WORKDIR) $(SPISPY_WAVE) $(BUFCTRL_WAVE)
