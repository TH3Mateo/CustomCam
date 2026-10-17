################################################################################
# common.tcl - ustawienia wspolne wszystkich etapow buildu.
#
# Dolaczane przez source na poczatku kazdego skryptu etapu.
# Parametry przychodza z Makefile przez -tclargs, zeby nie duplikowac
# konfiguracji w dwoch miejscach.
################################################################################

# --- Parametry z Makefile (-tclargs PRJ TOP OUTDIR) ---
if {$argc < 3} {
    error "Uzycie: -tclargs <projekt> <modul_top> <katalog_wyjsciowy>"
}
set PRJ    [lindex $argv 0]
set TOP    [lindex $argv 1]
set OUTDIR [lindex $argv 2]

# Nazwa czesci w formacie Tcl. Oznaczenie handlowe XC7K325T-2FFG676C
# zapisuje sie tu jako xc7k325tffg676-2 (bez litery zakresu temperatury
# i bez separatorow) - inaczej get_parts/synth_design nie znajduje czesci.
set PART "xc7k325tffg676-2"

set RPTDIR "$OUTDIR/reports"
file mkdir $OUTDIR
file mkdir $RPTDIR

# --- Obsluga bledow ---
# NIE owijamy krokow w catch. Zmierzone: vivado -mode batch w 2017.4 sam
# przerywa skrypt i zwraca kod 1 przy bledzie (synteza, DRC, blad Tcl),
# a vivado.bat konczy sie "exit /b %errorlevel%", wiec kod dochodzi do make.
# catch POLKNALBY blad i zamienil porazke w cichy sukces - odwrotnie do
# tego, o co nam chodzi.
#
# Podnosimy natomiast rangę wybranych ostrzezen. Krytyczne ostrzezenia
# oznaczaja zwykle realny problem (niedopiete constrainty, wnioskowana
# latch), ktory na sprzecie objawi sie jako trudny do znalezienia blad.
set_msg_config -severity {CRITICAL WARNING} -new_severity ERROR

# Wyjatek: brak licencji IP ma zostac ostrzezeniem, a nie zabijac build -
# chcemy zobaczyc raport zasobow nawet gdy IP nie da sie zaimplementowac.
# (Regula bez dopasowania jest nieszkodliwa, wiec zostawiamy na przyszlosc.)

proc naglowek {tekst} {
    puts ""
    puts "================================================================"
    puts " $tekst"
    puts "================================================================"
}
