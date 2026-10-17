################################################################################
# synth.tcl - synteza RTL.
#
# Wejscie : zrodla .sv + constrainty .xdc (sciezki wyliczane z $PRJ)
# Wyjscie : $OUTDIR/post_synth.dcp + raporty w $OUTDIR/reports/
################################################################################
source [file dirname [info script]]/common.tcl

naglowek "SYNTEZA: $TOP ($PART)"

# --- Zrodla ---
# read_verilog -sv jest WYMAGANE dla SystemVerilog - bez -sv narzedzie
# czyta pliki jako zwykly Verilog i wywraca sie na package/always_ff.
# Kolejnosc ma znaczenie: pakiet musi byc przeczytany przed modulami,
# ktore go importuja (tak samo jak w iverilog przy Gowin).
set SRC_DIR "$PRJ/src/hdl"
set pkg_files [lsort [glob -nocomplain "$SRC_DIR/*_pkg.sv"]]
set rtl_files {}
foreach f [lsort [glob -nocomplain "$SRC_DIR/*.sv"]] {
    if {[lsearch -exact $pkg_files $f] < 0} { lappend rtl_files $f }
}
if {[llength $pkg_files] == 0 && [llength $rtl_files] == 0} {
    error "Brak zrodel .sv w $SRC_DIR"
}
foreach f [concat $pkg_files $rtl_files] {
    puts "  zrodlo: $f"
    read_verilog -sv $f
}

# --- Constrainty ---
set xdc "$PRJ/src/constraints/$PRJ.xdc"
if {![file exists $xdc]} { error "Brak pliku constraintow: $xdc" }
puts "  constrainty: $xdc"
read_xdc $xdc

# --- Synteza ---
# -flatten_hierarchy rebuilt (domyslne): splaszcza na czas optymalizacji,
# potem odtwarza hierarchie w raportach - najlepsze do diagnostyki.
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

write_checkpoint -force $OUTDIR/post_synth.dcp

report_utilization      -file $RPTDIR/post_synth_util.rpt
report_timing_summary   -file $RPTDIR/post_synth_timing.rpt

naglowek "SYNTEZA OK -> $OUTDIR/post_synth.dcp"
