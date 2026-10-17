################################################################################
# impl.tcl - implementacja (opt / place / phys_opt / route).
#
# Wejscie : $OUTDIR/post_synth.dcp
# Wyjscie : $OUTDIR/post_route.dcp + raporty
#
# Tu jest bramka na timing - build MUSI sie wywalic przy naruszeniu, inaczej
# bitstream powstalby z projektu, ktory na sprzecie nie zadziala. Wzorzec
# z run_bft_kintex7_batch.tcl tego NIE robi (zapisuje raport, ktorego nikt
# nie czyta), wiec dokladamy to sami.
################################################################################
source [file dirname [info script]]/common.tcl

naglowek "IMPLEMENTACJA: $TOP"

open_checkpoint $OUTDIR/post_synth.dcp

opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $OUTDIR/post_route.dcp

report_utilization        -file $RPTDIR/post_route_util.rpt
report_timing_summary     -file $RPTDIR/post_route_timing.rpt
report_clock_utilization  -file $RPTDIR/clock_util.rpt
report_drc                -file $RPTDIR/drc.rpt

# --- Zrzut faktycznie uzytego pinoutu ---
# To jest zrodlo prawdy dla schematu PCB. Metoda przejeta z pracy na Gowin
# (.claude/WYNIKI_usb_gpif.md): "Pinout dla PCB nalezy generowac tak,
# a nie wymyslac recznie."
write_xdc -no_fixed_only -force $RPTDIR/${TOP}_impl.xdc

# --- Bramka na timing ---
# UWAGA: get_property SLACK [get_timing_paths] zwraca w non-project mode
# PUSTA wartosc, a get_property STATS.WNS [get_runs] wywala sie bledem
# (brak obiektow "run" poza project mode). Jedyna niezawodna metoda to
# dopasowanie tekstu w raporcie zwroconym jako string.
set podsumowanie [report_timing_summary -no_header -no_detailed_paths -return_string]
if {![string match -nocase {*timing constraints are met*} $podsumowanie]} {
    puts $podsumowanie
    error "TIMING NIESPELNIONY - szczegoly w $RPTDIR/post_route_timing.rpt"
}

naglowek "IMPLEMENTACJA OK, timing spelniony -> $OUTDIR/post_route.dcp"
