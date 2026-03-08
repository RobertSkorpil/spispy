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

INJECTOR_SRC := mux.vhdl arbiter.vhdl range_register.vhdl injector.vhdl
INJECTOR_TB  := injector_tb.vhdl

ARBITER_SRC  := arbiter.vhdl
ARBITER_TB   := arbiter_tb.vhdl

# Wave output files
SPISPY_WAVE  := spispy_tb.fst
BUFCTRL_WAVE := bufctrl_tb.fst
INJECTOR_WAVE := injector_tb.fst
ARBITER_WAVE := arbiter_tb.fst

# ---------------------------------------------------------------
# Default: run all testbenches
# ---------------------------------------------------------------
.PHONY: all clean spispy bufctrl injector arbiter waves

all: spispy bufctrl injector arbiter

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
# injector testbench
# ---------------------------------------------------------------
injector: $(INJECTOR_WAVE)
	@echo "=== injector_tb complete — waveform: $(INJECTOR_WAVE) ==="

$(INJECTOR_WAVE): $(INJECTOR_SRC) $(INJECTOR_TB)
	$(NVC) --std=2008 -a $(INJECTOR_SRC) $(INJECTOR_TB)
	$(NVC) --std=2008 -e injector_tb
	$(NVC) --std=2008 -r injector_tb --wave=$(INJECTOR_WAVE)

# ---------------------------------------------------------------
# arbiter testbench
# ---------------------------------------------------------------
arbiter: $(ARBITER_WAVE)
	@echo "=== arbiter_tb complete — waveform: $(ARBITER_WAVE) ==="

$(ARBITER_WAVE): $(ARBITER_SRC) $(ARBITER_TB)
	$(NVC) --std=2008 -a $(ARBITER_SRC) $(ARBITER_TB)
	$(NVC) --std=2008 -e arbiter_tb
	$(NVC) --std=2008 -r arbiter_tb --wave=$(ARBITER_WAVE)

# ---------------------------------------------------------------
# Open waveforms in GTKWave
# ---------------------------------------------------------------
waves: all
	gtkwave $(SPISPY_WAVE) &
	gtkwave $(BUFCTRL_WAVE) &
	gtkwave $(INJECTOR_WAVE) &

# ---------------------------------------------------------------
# Clean build artifacts
# ---------------------------------------------------------------
clean:
	rm -rf $(WORKDIR) $(SPISPY_WAVE) $(BUFCTRL_WAVE) $(INJECTOR_WAVE) $(ARBITER_WAVE)
