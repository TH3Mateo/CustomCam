################################################################################
# Makefile - toolchain Vivado 2017.4 dla XC7K325T-2FFG676C
#
# Adapter USB 3.0 -> eDP. Buduje z linii polecen, bez GUI (non-project mode).
# Odpowiednik Makefile z poprzedniej platformy Gowin (old/usb_gpif/Makefile).
#
# Uzycie:
#   make simulate           - symulacja behawioralna (XSim)
#   make synth              - synteza
#   make impl               - implementacja (opt/place/route) + bramka timingu
#   make bit                - bitstream
#   make all                - synteza + impl + bitstream
#   make clean              - czyszczenie wynikow
#   make check              - weryfikacja srodowiska
#   make PRJ=inny_modul ... - przelaczenie projektu
#
# UWAGA O WYKRYWANIU BLEDOW (wszystko ZMIERZONE, nie zalozone):
#
#   vivado.bat / xvlog.bat / xelab.bat / xsim.bat
#       propaguja kod bledu poprawnie - same nie maja "exit /b", ale wolaja
#       loader.bat, ktory go ma. Zmierzone: xvlog na zepsutym pliku -> rc=1.
#
#   ALE: $fatal w testbenchu konczy sie kodem 0.
#       Zmierzone: xelab -R z $fatal(1) -> rc=0, xsim --runall -> rc=0.
#       Symulacja moze WYPISAC banner PASS i zaraz potem paść przez $fatal.
#
# Dlatego bramka symulacji jest DWUSTOPNIOWA i obie warstwy sa konieczne:
#   1. brak "Fatal:"/"Error:" w logu  - lapie $fatal mimo bannera PASS
#   2. obecnosc bannera PASS          - lapie TB, ktory padl przed koncem
# Zmierzone na przypadku granicznym (TB drukuje PASS, potem $fatal):
# warstwa 2 by NIE zadzialala, warstwa 1 zlapala. I odwrotnie przy cichym
# padzie. Zadna z osobna nie wystarcza.
#
# SHELL=bash + pipefail: bez tego "cmd | tee" zwraca kod tee (zawsze 0),
# co maskowaloby porazke xvlog/xelab.
################################################################################

# Bash z pipefail: w potoku "narzedzie | tee log" bez tego make widzi
# kod wyjscia tee (zawsze 0), a nie narzedzia.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# --- Konfiguracja ---
PRJ      ?= hello
TOP      ?= $(PRJ)_top
PART     := xc7k325tffg676-2

VIVADO_ROOT := C:/Xilinx/Vivado/2017.4
VIVADO      := $(VIVADO_ROOT)/bin/vivado.bat
XVLOG       := $(VIVADO_ROOT)/bin/xvlog.bat
XELAB       := $(VIVADO_ROOT)/bin/xelab.bat
XSIM        := $(VIVADO_ROOT)/bin/xsim.bat

# -nolog/-nojournal: bez smiecenia w repo (logi i tak zbieramy do build/)
VOPTS    := -mode batch -nolog -nojournal -notrace

BUILD    := build
OUTDIR   := $(BUILD)/$(PRJ)
RPTDIR   := $(OUTDIR)/reports
SIMDIR   := $(BUILD)/sim

SRC_DIR  := $(PRJ)/src/hdl
TB_DIR   := $(PRJ)/src/tb
XDC      := $(PRJ)/src/constraints/$(PRJ).xdc

# Pakiety PRZED reszta zrodel - importujace moduly nie skompiluja sie inaczej.
PKG_SRC  := $(wildcard $(SRC_DIR)/*_pkg.sv)
RTL_SRC  := $(filter-out $(PKG_SRC),$(wildcard $(SRC_DIR)/*.sv))
TB_SRC   := $(wildcard $(TB_DIR)/*.sv)
ALL_SRC  := $(PKG_SRC) $(RTL_SRC)

SIM_TOP  := $(PRJ)_tb
SIM_SNAP := $(PRJ)_snap
SIM_LOG  := $(SIMDIR)/$(PRJ)_sim.log

TCLARGS  := -tclargs $(PRJ) $(TOP) $(OUTDIR)

.PHONY: all check simulate synth impl bit clean distclean help

all: bit

help:
	@echo "Cele: check simulate synth impl bit all clean"
	@echo "Projekt: PRJ=$(PRJ)  top=$(TOP)  czesc=$(PART)"

################################################################################
# Weryfikacja srodowiska
################################################################################
check:
	@test -f "$(VIVADO)" || { echo "BLAD: brak $(VIVADO)"; exit 1; }
	@echo "OK: vivado.bat"
	@test -n "$(ALL_SRC)" || { echo "BLAD: brak zrodel w $(SRC_DIR)"; exit 1; }
	@echo "OK: zrodla: $(ALL_SRC)"
	@test -f "$(XDC)" || { echo "BLAD: brak constraintow $(XDC)"; exit 1; }
	@echo "OK: constrainty: $(XDC)"
	@echo "Konfiguracja poprawna."

################################################################################
# Symulacja (XSim)
#
# Bramka na wynik jest DWUSTOPNIOWA, bo kod wyjscia jest bezuzyteczny:
#   1. brak linii "Fatal:"/"Error:" w logu
#   2. OBECNOSC bannera PASS z testbencha
# Sam brak bledow nie wystarcza - testbench moglby sie wysypac przed
# wypisaniem czegokolwiek i log bylby "czysty".
################################################################################
simulate: $(SIM_LOG)

$(SIM_LOG): $(ALL_SRC) $(TB_SRC)
	@mkdir -p $(SIMDIR)
	@echo "=== Kompilacja (xvlog) ==="
	cd $(SIMDIR) && $(XVLOG) -sv $(addprefix $(CURDIR)/,$(ALL_SRC) $(TB_SRC)) 2>&1 | tee xvlog.log
	@grep -qE "^ERROR" $(SIMDIR)/xvlog.log && { echo "BLAD kompilacji"; exit 1; } || true
	@echo "=== Elaboracja (xelab) ==="
	cd $(SIMDIR) && $(XELAB) -debug typical -relax -timescale 1ns/1ps \
		-top $(SIM_TOP) -snapshot $(SIM_SNAP) 2>&1 | tee xelab.log
	@grep -qE "^ERROR" $(SIMDIR)/xelab.log && { echo "BLAD elaboracji"; exit 1; } || true
	@echo "=== Symulacja (xsim) ==="
	cd $(SIMDIR) && $(XSIM) $(SIM_SNAP) --runall 2>&1 | tee $(notdir $(SIM_LOG))
	@grep -qE "^Fatal:|^Error:" $(SIM_LOG) && { echo ">>> SYMULACJA: FAIL (blad w logu)"; exit 1; } || true
	@grep -q "=== PASS" $(SIM_LOG) || { echo ">>> SYMULACJA: FAIL (brak bannera PASS)"; exit 1; }
	@echo ">>> SYMULACJA: PASS"

################################################################################
# Synteza / implementacja / bitstream
#
# Etapy powiazane przez checkpointy .dcp - make wznawia od miejsca, w ktorym
# cos sie zmienilo, zamiast powtarzac calosc (place&route na K325T to minuty).
################################################################################
synth: $(OUTDIR)/post_synth.dcp

$(OUTDIR)/post_synth.dcp: $(ALL_SRC) $(XDC) scripts/synth.tcl scripts/common.tcl
	@mkdir -p $(RPTDIR)
	$(VIVADO) $(VOPTS) -source scripts/synth.tcl $(TCLARGS) -log $(OUTDIR)/synth.log
	@test -f $@ || { echo "BLAD: brak $@"; exit 1; }

impl: $(OUTDIR)/post_route.dcp

$(OUTDIR)/post_route.dcp: $(OUTDIR)/post_synth.dcp scripts/impl.tcl scripts/common.tcl
	$(VIVADO) $(VOPTS) -source scripts/impl.tcl $(TCLARGS) -log $(OUTDIR)/impl.log
	@test -f $@ || { echo "BLAD: brak $@"; exit 1; }

bit: $(OUTDIR)/$(TOP).bit

$(OUTDIR)/$(TOP).bit: $(OUTDIR)/post_route.dcp scripts/bitstream.tcl scripts/common.tcl
	$(VIVADO) $(VOPTS) -source scripts/bitstream.tcl $(TCLARGS) -log $(OUTDIR)/bit.log
	@test -f $@ || { echo "BLAD: brak bitstreamu"; exit 1; }
	@echo ">>> BITSTREAM: $@"
	@ls -lh $@

################################################################################
# Czyszczenie
################################################################################
clean:
	rm -rf $(BUILD)
	rm -f vivado*.log vivado*.jou *.pb
	@echo "Wyczyszczono."

distclean: clean
	rm -rf .Xil
