################################################################################
# hello.xdc - constrainty modulu testowego toolchainu.
#
# UWAGA: TO JEST ATRAPA. Plyta PCB nie istnieje, wiec przypisania pinow sa
# WSTEPNE i sluza wylacznie temu, zeby przeplyw doszedl do bitstreamu.
# Realny pinout powstanie razem ze schematem i - zgodnie z metoda opisana
# w .claude/WYNIKI_usb_gpif.md - ma byc GENEROWANY przez narzedzie
# (write_xdc po udanym PnR), a nie wymyslany recznie.
#
# Piny odczytane z bazy urzadzenia (get_package_pins dla xc7k325tffg676-2),
# nie zgadniete. Wszystkie w banku 12 (HR - dopuszcza LVCMOS33).
#
# KAZDY port musi miec PACKAGE_PIN i IOSTANDARD, inaczej write_bitstream
# odmawia - patrz naglowek examples/Vivado_Tutorial/Sources/bft_full_kintex7.xdc:
#   "LOC and IOSTANDARDS set for all IOs which is required for generating
#    a Bitstream"
################################################################################

# --- Zegar ---
# Y23 = IO_L12P_T1_MRCC_12. MRCC (Multi-Region Clock Capable) - pin zdolny
# napedzac globalna siec zegarowa. Wazne: w GW2AR rejestr negedge trafil na
# zwykly routing (WARN PR1014 w .claude/WYNIKI_usb_gpif.md) i to bylo
# nierozwiazane ryzyko. Tutaj od poczatku wybieramy pin zegarowy swiadomie.
set_property PACKAGE_PIN Y23      [get_ports CLK]
set_property IOSTANDARD  LVCMOS33 [get_ports CLK]

create_clock -period 10.000 -name sys_clk [get_ports CLK]

# --- Reset ---
set_property PACKAGE_PIN U21      [get_ports RESET]
set_property IOSTANDARD  LVCMOS33 [get_ports RESET]

# Reset jest asynchroniczny wzgledem zegara jako sygnal zewnetrzny (przycisk),
# ale w RTL jest probkowany synchronicznie. Wylaczamy go z analizy wejsciowej,
# zeby nie generowal falszywych naruszen - nie ma sensownego input delay
# dla przycisku.
set_false_path -from [get_ports RESET]

# --- LED ---
set_property PACKAGE_PIN U22      [get_ports LED_HEART]
set_property IOSTANDARD  LVCMOS33 [get_ports LED_HEART]

set_property PACKAGE_PIN V22      [get_ports {LED_COUNT[0]}]
set_property PACKAGE_PIN U24      [get_ports {LED_COUNT[1]}]
set_property PACKAGE_PIN U25      [get_ports {LED_COUNT[2]}]
set_property PACKAGE_PIN V23      [get_ports {LED_COUNT[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {LED_COUNT[*]}]

# Wyjscia na LED nie maja odbiornika o wymaganiach czasowych - bez tego
# narzedzie raportowaloby nieokreslone sciezki wyjsciowe.
set_false_path -to [get_ports {LED_HEART LED_COUNT[*]}]
