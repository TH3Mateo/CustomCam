################################################################################
# Makefile dla projektu FPGA Gowin
#
# Ten Makefile automatyzuje proces syntezy, routingu i generowania bitstreamu
# dla projektów Gowin FPGA przy użyciu narzędzi command-line.
#
# Przed użyciem:
#   1. Uruchom ./setup_gowin_env.sh
#   2. Upewnij się, że MAC address kontenera to 00:15:5D:CA:03:B8
#   3. Przeładuj kontener po aktualizacji docker-compose.yml
#
# Użycie:
#   make all          - kompletny workflow (synteza + routing + bitstream)
#   make synthesize   - tylko synteza
#   make route        - synteza i routing
#   make bitstream    - generowanie bitstreamu
#   make simulate     - symulacja behawioralna (iverilog + gtkwave)
#   make clean        - czyszczenie plików wyjściowych
#   make distclean    - pełne czyszczenie (z plikami tymczasowymi)
#   make help         - wyświetlenie pomocy
################################################################################

# Kolory dla output
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

################################################################################
# Konfiguracja projektu
################################################################################

# Wariant buildu. Katalog zawiera dwa projekty Gowin dzielace to samo drzewo src/:
#   usb_gpif      - rdzen (top: usb_gpif), uzywany przez top_module
#   usb_gpif_dev  - plyta bring-up (top: usb_gpif_dev), instancjonuje rdzen
# Top modulu NIE ustawia sie nigdzie jawnie - GowinSynthesis wykrywa go jako
# modul nieinstancjonowany przez zaden inny, wiec o topie decyduje wylacznie
# lista plikow w wybranym .gprj.
#   make                        - wariant rdzenia
#   make PRJ=usb_gpif_dev      - wariant bring-up
PRJ          ?= usb_gpif

PROJECT_NAME := $(PRJ)
TOP_MODULE   := $(PRJ)
DEVICE       := GW2AR-LV18QN88C8/I7
DEVICE_NAME  := GW2AR-18C
BOARD := tangnano20k


# Katalogi
SRC_DIR      := src
IMPL_DIR     := impl
SYNTH_DIR    := $(IMPL_DIR)/gwsynthesis
PNR_DIR      := $(IMPL_DIR)/pnr
TEMP_DIR     := $(IMPL_DIR)/temp

# Plik projektu
PROJECT_FILE := $(PROJECT_NAME).gprj

# Pliki źródłowe - automatycznie wyodrębnione z .gprj
VERILOG_SRC  := $(shell grep 'type="file.verilog"' $(PROJECT_FILE) | sed -n 's/.*path="\([^"]*\)".*/\1/p')

CST_FILE     := $(SRC_DIR)/constraints/$(PROJECT_NAME).cst
SDC_FILE     := $(SRC_DIR)/constraints/$(PROJECT_NAME).sdc
GAO_FILE     := $(SRC_DIR)/$(PROJECT_NAME).rao
SIM_DIR      := outputs/sim
SIM_TB       := $(SRC_DIR)/tb/$(PROJECT_NAME)_tb.sv
SIM_TOP      := $(PROJECT_NAME)_tb
SIM_OUT      := $(SIM_DIR)/$(PROJECT_NAME)_tb.out
SIM_INC_DIRS := -I $(SRC_DIR)/hdl
SIM_VCD      := $(SIM_DIR)/$(PROJECT_NAME)_tb.vcd
SIM_DEFS     := -D SIM
# Konfiguracja rdzenia - wspolna dla obu wariantow, nie zalezy od PRJ.
BUILD_CONFIG  := $(TEMP_DIR)/usb_gpif_build_config.svh

# Pliki wyjściowe
SYNTH_PRJ    := $(SYNTH_DIR)/$(PROJECT_NAME).prj
SYNTH_RESULT := $(SYNTH_DIR)/$(PROJECT_NAME).vg
PNR_RESULT   := $(PNR_DIR)/$(PROJECT_NAME).rpt.txt
BITSTREAM    := $(IMPL_DIR)/pnr/$(PROJECT_NAME).fs

# Narzędzia Gowin
GOWIN_HOME   := /home/th3m/Programs/GOWIN_fpga/IDE
GOWIN_SH     := $(GOWIN_HOME)/bin/gw_sh
GOWIN_SYNTH  := $(GOWIN_HOME)/bin/GowinSynthesis
# Biblioteka prymityw Gowin - RTL instancjonuje TLVDS_OBUF (pary LVDS).
PRIM_SIM     := $(GOWIN_HOME)/simlib/gw2a/prim_sim.v

# Skrypty
GEN_SYNTH_SCRIPT := generate_synthesis_project.py
GEN_PNR_SCRIPT   := generate_pnr_script.py
# Per-wariant: oba projekty dziela katalog impl/, wiec wspolny run_pnr.tcl
# nadpisywalby sie miedzy buildami.
PNR_SCRIPT       := impl/pnr/run_pnr_$(PROJECT_NAME).tcl

################################################################################
# Targets główne
################################################################################

.PHONY: all help clean distclean check $(BUILD_CONFIG)

# Target domyślny
all: $(BUILD_CONFIG) bitstream
	@echo -e "$(GREEN)=========================================="
	@echo -e "Kompilacja zakończona pomyślnie!"
	@echo -e "==========================================$(NC)"
	@echo -e "Plik bitstreamu: $(BITSTREAM)"
	@echo -e "Raport timing: $(PNR_RESULT)"

help:
	@echo -e "$(BLUE)Dostępne targety:$(NC)"
	@echo "  make all          - kompletny workflow (synteza + routing + bitstream)"
	@echo "  make synthesize   - synteza RTL"
	@echo "  make route        - place and route"
	@echo "  make bitstream    - generowanie bitstreamu"
	@echo "  make simulate     - symulacja behawioralna (iverilog + gtkwave)"
	@echo "  make view         - otwarcie przebiegów VCD w GTKWave"
	@echo "  make flash        - wgranie bitstreamu do SRAM FPGA"
	@echo "  make upload       - wgranie bitstreamu do flash FPGA"
	@echo "  make clean        - usunięcie plików wyjściowych"
	@echo "  make distclean    - pełne czyszczenie"
	@echo "  make settings     - konfiguracja portu szeregowego (minicom)"

################################################################################
# Sprawdzanie konfiguracji
################################################################################

check:
	@echo -e "$(BLUE)Sprawdzanie konfiguracji środowiska...$(NC)"
	@if [ ! -x "$(GOWIN_SH)" ]; then \
		echo -e "$(RED)✗ gw_sh nie znalezione w $(GOWIN_SH)$(NC)"; \
		exit 1; \
	else \
		echo -e "$(GREEN)✓ gw_sh znalezione$(NC)"; \
	fi
	@if [ ! -f "$(PROJECT_FILE)" ]; then \
		echo -e "$(RED)✗ Plik projektu $(PROJECT_FILE) nie istnieje$(NC)"; \
		exit 1; \
	else \
		echo -e "$(GREEN)✓ Plik projektu $(PROJECT_FILE) OK$(NC)"; \
	fi
	@for src in $(VERILOG_SRC); do \
		if [ ! -f "$$src" ]; then \
			echo -e "$(RED)✗ Plik źródłowy $$src nie istnieje$(NC)"; \
			exit 1; \
		fi; \
	done
	@echo -e "$(GREEN)✓ Wszystkie pliki źródłowe OK$(NC)"
	@if [ ! -f "$(CST_FILE)" ]; then \
		echo -e "$(RED)✗ Plik constraints $(CST_FILE) nie istnieje$(NC)"; \
		exit 1; \
	else \
		echo -e "$(GREEN)✓ Plik constraints OK$(NC)"; \
	fi
	@echo -e "$(GREEN)Konfiguracja poprawna!$(NC)"

################################################################################
# Synteza
################################################################################

.PHONY: synthesize syn

synthesize syn: check $(BUILD_CONFIG) $(SYNTH_RESULT)

$(BUILD_CONFIG):
	@mkdir -p $(TEMP_DIR)
	@printf '%s\n' '`ifndef USB_GPIF_BUILD_CONFIG_SVH' > $(BUILD_CONFIG)
	@printf '%s\n' '`define USB_GPIF_BUILD_CONFIG_SVH' >> $(BUILD_CONFIG)
	@printf '%s\n' '`endif' >> $(BUILD_CONFIG)

$(SYNTH_PRJ): $(PROJECT_FILE)
	@echo -e "$(BLUE)Generowanie pliku projektu syntezy...$(NC)"
	@python3 $(GEN_SYNTH_SCRIPT) $(PROJECT_FILE) $(SYNTH_PRJ)

$(SYNTH_RESULT): $(SYNTH_PRJ) $(VERILOG_SRC) $(CST_FILE) $(SDC_FILE)
	@echo -e "$(YELLOW)=========================================="
	@echo -e "Uruchamianie syntezy RTL..."
	@echo -e "==========================================$(NC)"
	@mkdir -p $(SYNTH_DIR) $(TEMP_DIR)
	@echo -e "$(BLUE)Wykonywanie syntezy...$(NC)"
	$(GOWIN_SYNTH) -prj $(SYNTH_PRJ)
	@if [ -f "$(SYNTH_RESULT)" ]; then \
		echo -e "$(GREEN)✓ Synteza zakończona pomyślnie$(NC)"; \
		echo -e "Raport: $(SYNTH_DIR)/$(PROJECT_NAME)_syn.rpt.html"; \
	else \
		echo -e "$(RED)✗ Synteza nie powiodła się$(NC)"; \
		exit 1; \
	fi

################################################################################
# Place and Route
################################################################################

.PHONY: route pnr

route pnr: synthesize $(PNR_RESULT)

$(PNR_SCRIPT): $(PROJECT_FILE)
	@echo -e "$(BLUE)Generowanie skryptu Place and Route...$(NC)"
	@python3 $(GEN_PNR_SCRIPT) $(PROJECT_FILE) $(PNR_SCRIPT)

$(PNR_RESULT): $(PNR_SCRIPT) $(SYNTH_RESULT)
	@echo -e "$(YELLOW)=========================================="
	@echo -e "Uruchamianie Place and Route..."
	@echo -e "==========================================$(NC)"
	@mkdir -p $(PNR_DIR)
	@cp device.cfg $(PNR_DIR)/device.cfg 2>/dev/null || true
	@echo -e "$(BLUE)Wykonywanie place and route...$(NC)"
	$(GOWIN_SH) $(PNR_SCRIPT)
	@if [ -f "$(PNR_RESULT)" ]; then \
		echo -e "$(GREEN)✓ Place and Route zakończone pomyślnie$(NC)"; \
		echo -e "Raport: $(PNR_RESULT)"; \
	else \
		echo -e "$(RED)✗ Place and Route nie powiodło się$(NC)"; \
		exit 1; \
	fi

################################################################################
# Generowanie bitstreamu
################################################################################

.PHONY: bitstream bit

bitstream bit: route $(BITSTREAM)

$(BITSTREAM): $(PNR_RESULT)
	@echo -e "$(YELLOW)=========================================="
	@echo -e "Weryfikacja bitstreamu..."
	@echo -e "==========================================$(NC)"
	@if [ -f "$(BITSTREAM)" ]; then \
		echo -e "$(GREEN)✓ Bitstream wygenerowany pomyślnie$(NC)"; \
		echo -e "Plik: $(BITSTREAM)"; \
		ls -lh $(BITSTREAM); \
		echo ""; \
		echo -e "$(GREEN)Gotowy do wgrania na FPGA!$(NC)"; \
	else \
		echo -e "$(RED)✗ Nie udało się wygenerować bitstreamu$(NC)"; \
		exit 1; \
	fi

################################################################################
# Czyszczenie
################################################################################

.PHONY: clean distclean

clean:
	@echo -e "$(YELLOW)Czyszczenie plików wyjściowych...$(NC)"
	rm -rf $(IMPL_DIR)
	rm -f *.log
	@echo -e "$(GREEN)✓ Pliki wyjściowe usunięte$(NC)"

distclean: clean
	@echo -e "$(YELLOW)Pełne czyszczenie projektu...$(NC)"
	rm -f *.rpt.html *.rpt.txt
	rm -f *_syn.json
	@echo -e "$(GREEN)✓ Projekt wyczyszczony$(NC)"

################################################################################
# Targety pomocnicze
################################################################################

.PHONY: simulate view

# Lista zrodel czytana z wybranego .gprj ($(VERILOG_SRC)), wiec symulacja
# podaza za wariantem PRJ bez osobnej listy plikow.
simulate: $(BUILD_CONFIG)
	@mkdir -p $(SIM_DIR)
	# Zrodla PRZED testbenchem: pakiet musi byc skompilowany, zanim iverilog
	# napotka `import usb_gpif_pkg::*` w naglowku TB.
	@iverilog -g2012 $(SIM_DEFS) $(SIM_INC_DIRS) -s $(SIM_TOP) -o $(SIM_OUT) $(VERILOG_SRC) $(SIM_TB) $(PRIM_SIM)
	@vvp $(SIM_OUT)


view:
	@echo -e "$(BLUE)Otwieranie przebiegów w GTKWave...$(NC)"
	@if [ ! -f "$(SIM_VCD)" ]; then \
		echo -e "$(RED)✗ Nie znaleziono pliku przebiegów: $(SIM_VCD)$(NC)"; \
		echo "  Najpierw uruchom: make simulate"; \
		exit 1; \
	fi
	@if command -v gtkwave >/dev/null 2>&1; then \
		gtkwave $(SIM_VCD) -g; \
	else \
		echo -e "$(RED)✗ Nie znaleziono narzędzia: gtkwave$(NC)"; \
		exit 1; \
	fi

################################################################################
# Phony targets
################################################################################

.PHONY: all help check synthesize syn route pnr bitstream bit clean distclean \
		simulate view flash upload settings


flash: 
	@echo "==> Wgrywam bitstream do FPGA ($(BOARD))..."
	openFPGALoader --bulk-erase -b $(BOARD) $(BITSTREAM) --verify 
	@echo "==> Wgrywanie zakończone"

upload:
	@echo "==> Wgrywam bitstream do FPGA flash ($(BOARD))..."
	openFPGALoader --bulk-erase -b $(BOARD) -f $(BITSTREAM) --verify 
	@echo "==> Wgrywanie zakończone"

settings:
	stty -F /dev/ttyUSB0 115200 raw -echo
	minicom -b 115200 -D /dev/ttyUSB1

run: all flash 
