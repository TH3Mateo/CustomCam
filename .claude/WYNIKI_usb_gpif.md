# Wyniki: usb_gpif (2026-08-27)

Zmierzone, nie szacowane. Wariant `usb_gpif_dev`, GW2AR-LV18QN88C8/I7.

## Symulacja - PASS

```
Przeslano slow przez FX3       : 4096
Slow zaliczonych przez checker : 4096
led_error                      : 0
=== PASS: wszystkie testy zaliczone ===
```
Sprawdzone: ciaglosc strumienia, 166 granic buforow DMA, model FX3 z realnymi
tCO=7ns i tCFLG=8ns, odbiorca bez przerwy gotowy (`ready_i=1` - najostrzejszy
przypadek, FIFO chwilami pustoszeje).

### Znaleziony i naprawiony blad: gubione slowo na granicy bufora

Objaw: checker zaliczal 4062 z 4096 - dokladnie 1 slowo na kazda granice DMA.

Diagnoza (sonda, nie zgadywanie): slowo docieralo na magistrale I do rejestru
`dq_r`, ale ze znacznikiem `vld=0`:
```
  DQ=0xfd   @2837000 SLOEn=0 SLRDn=0
  dq_r=0xfd @2847000 vld=0      <-- dane sa, waznosci brak
```

Przyczyna: `vld_r` bylo bramkowane przez `oe_hist_r`, ktore zawieralo
`FLAG_EMPTY`:
```systemverilog
vld_r <= word_taken && oe_hist_r[2];   // oe_hist_r <= {..., rd_active_r && FLAG_EMPTY}
```
FX3 opuszcza FLAG z wyprzedzeniem (tCFLG=8ns), wiec ostatnie slowa kazdego
bufora - juz zamowione i faktycznie dostarczone - traciły waznosc.

Naprawa: `vld_r <= word_taken`. Znacznik idzie ta sama droga co dane
(2 stopnie: negedge + posedge) i nie jest gaszony flaga.

**Wniosek na przyszlosc:** FLAG_EMPTY sluzy WYLACZNIE do decyzji "czy zamawiac
kolejne slowo". Nigdy do oceny waznosci slowa juz zamowionego - to dwie rozne
rzeczy, rozjezdzajace sie o tCFLG + latencje potoku.

## Zasoby - kluczowa liczba dla oceny "czy calosc sie zmiesci"

| Zasob | Uzycie | Dostepne | % |
|---|---:|---:|---:|
| LUT/ALU | 257 | 20 736 | 2% |
| Rejestry | 221 | 15 750 | 2% |
| CLS | 204 | 10 368 | 2% |
| **BSRAM (SDPB)** | **1** | **46** | **3%** |
| DSP | 0 | 48 | 0% |
| PLL | 0 | 2 | 0% |
| I/O | 39 | ~57 | - |

**Wniosek: modul USB jest praktycznie darmowy** (<1% logiki, 1 z 46 BSRAM).
Cale 20.7k LUT i 45 BSRAM zostaje na dekoder MJPEG i nadajnik LVDS - a to one
beda decydowac, czy projekt zmiesci sie w GW2AR-18.

Uwaga: PLL=0, bo wariant dev bierze zegar wprost z pinu. Docelowo 1 PLL na
wytworzenie PCLK (z 2 dostepnych w QN88).

## Timing - 0 naruszen

```
Numbers of Setup Violated Endpoints : 0
Numbers of Hold Violated Endpoints  : 0
Constraint 100.000 MHz -> Actual Fmax 111.241 MHz   (zapas ~11%)
Total Negative Slack: 0.000
```
Najgorsza sciezka: 1.011 ns zapasu (BSRAM -> licznik checkera).

## OSTRZEZENIE do rozwiazania przed sprzetem

```
WARN (PR1014): Generic routing resource will be used to clock signal 'clk_d'
by the specified constraint. And then it may lead to the excessive delay or skew
```
Rejestr probkujacy na zboczu opadajacym (`always_ff @(negedge clk)`) zostal
poprowadzony zwyklym routingiem zamiast siecia zegarowa. Przy 100 MHz i
marginesie 5 ns skew z generycznego routingu moze ten zapas zjesc.
Do zrobienia przy realnym sprzecie: wymusic siec zegarowa (BUFG/CLKDIV) albo
przejsc na IODELAY zamiast negedge.

## Korekta budzetu pinow - narzedzie mowi inaczej niz datasheet

```
ERROR (PA2024): The number(82) of ports exceeds the resource limit 53 regular
I/Os and 1 RECONFIG_N I/Os of current device, you can also use 4 JTAG, 4 SSPI
and 4 MSPI I/Os by configuring Dual-Purpose Pin as regular I/Os.
```
- **53 zwykle I/O** + 1 RECONFIG_N + 4 JTAG + 4 SSPI + 4 MSPI = 66 (zgodne z DS)
- Realnie dostepne przy zachowaniu JTAG i flash MSPI: **57**
- Zapotrzebowanie systemu: 35 (GPIF) + 20 (LVDS) + 2 (clk, reset) = **57**
- **Zero zapasu.** Kazdy dodatkowy sygnal wymaga oddania JTAG albo MSPI.

Piny **52, 54, 55, 56** sa odrzucane przez narzedzie jako dedykowane SSPI
(`PR2017`) MIMO `set_option -use_sspi_as_gpio 1` w run_pnr.tcl. IRIS ich uzywa,
wiec potrzebna jest dodatkowa konfiguracja - do ustalenia, jesli te 4 piny beda
potrzebne.

## Struktura: jeden projekt, nie dwa

Szkielet kompilacji samodzielnego rdzenia zostal **usuniety** (2026-08-28).
Rdzen `usb_gpif.sv` wystawia 32-bitowy strumien na porty - 82 porty przy 53
pinach, wiec jako top nigdy nie przeszedlby PnR. Jest czystym HDL do
instancjonowania wewnatrz ukladu i tak bedzie uzywany przez top-level.

Zostal jeden `.gprj` (top: `usb_gpif_dev`) i jedna para `.cst`/`.sdc`.


---

# Proba docelowego pinoutu (2026-08-28)

Do modulu `usb_gpif_dev` dodano **porty-placeholdery LVDS** (2 x 4 pary danych
+ 2 pary zegara = 20 pinow). Nie realizuja protokolu - wystawiaja dane ze
strumienia, zeby synteza ich nie usunela i zeby piny faktycznie byly zajete.
Cel: sprawdzic, czy komplet sygnalow docelowego systemu da sie fizycznie
rozmiescic w QN88, ZANIM powstanie PCB.

## Wynik: MIESCI SIE

```
I/O Port : 59      (DQ32 + PCLK/SLRD/SLOE/FLAG + 20 LVDS + clk + reset + 2 LED)
Bitstream: wygenerowany
Setup/Hold violated endpoints: 0 / 0
Actual Fmax: 104.944 MHz przy wymaganych 100 MHz   (zapas juz tylko ~5%)
Logic 277/20736 (2%) | Register 229 (2%) | CLS 231 (3%) | BSRAM 1 (3%)
```

## Warunek konieczny: rezygnacja z flash

Zeby zmiescic 59 pinow, trzeba bylo oddac na GPIO **oba** zestawy
dual-purpose:

| Grupa | Piny | Decyzja |
|---|---|---|
| JTAG | 5, 6, 7, 8 | **zostaje** - musi byc czym programowac uklad |
| MSPI | 59, 60, 61, 62 | **oddane na GPIO** -> BRAK FLASH |
| SSPI | 52, 54, 55, 56 | **oddane na GPIO** |

**Konsekwencja: bitstream nie przetrwa wylaczenia zasilania.** Programowanie
przez JTAG za kazdym razem. Jesli flash ma zostac, trzeba zejsc o 4 piny -
najtaniej przez LVDS 18bpp (3 pary danych zamiast 4 na wyswietlacz = -4 piny).

## Jak wlaczyc piny dual-purpose (nieoczywiste)

Wpisy w `.cst` **nie wystarczaja** - PnR odrzuca projekt (`PA2024`), bo widzi
limit 53 zwyklych I/O. `device.cfg` tez nie wystarcza, bo trafia dopiero do
generowania bitstreamu. Decyduja opcje w **`run_pnr.tcl`**, dodane w
`generate_pnr_script.py`:

```tcl
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
```
(To koryguje wczesniejsza obserwacje, ze piny SSPI sa "zablokowane" - byly,
dopoki brakowalo tej opcji.)

## LVDS: prawdziwe pary roznicowe (poprawione 2026-08-28)

Pierwsza wersja uzywala `IO_TYPE=LVCMOS33` i dwoch osobnych portow `_P`/`_N` -
to bylo **bledne**. Poprawnie:

- **`IO_TYPE=LVDS25`** (True LVDS / TLVDS). W GW2AR **nie ma** wariantu
  `LVDS33` ani 1.8V - datasheet zna tylko `LVDS25`, `LVDS25E`, `LVDSE`.
  Sam `LVDS25` dopuszcza VCCIO **2.5V lub 3.3V**, wiec nie wymusza
  dedykowanego napiecia banku.
- Pare tworzy prymitywa **`TLVDS_OBUF`** (jeden sygnal `I` -> para `O`/`OB`),
  a nie dwa niezalezne wyjscia.
- W `.cst` deklaruje sie **tylko pin dodatni**; ujemny narzedzie przydziela
  samo jako komplement pary.
- Symulacja wymaga biblioteki `$(GOWIN_HOME)/simlib/gw2a/prim_sim.v`
  (dodane do `PRIM_SIM` w Makefile).

### Zmierzone: 10 par TLVDS mieści sie razem z GPIF

```
I/O Port : 59      (32 DQ + 4 sterowanie GPIF + 20 LVDS + clk + reset + 2 LED)
Bitstream: wygenerowany,  Setup/Hold violated: 0 / 0
Actual Fmax: 118.174 MHz przy wymaganych 100   (zapas ~18%)
Logic 264/20736 (2%) | Register 229 (2%) | BSRAM 1 (3%)
```

Pary dobrane przez PnR (P/N, do przeniesienia na schemat PCB):

| Sygnal | P | N | | Sygnal | P | N |
|---|---:|---:|---|---|---:|---:|
| LVDS0_D[0] | 33 | 34 | | LVDS1_D[0] | 62 | 61 |
| LVDS0_D[1] | 31 | 32 | | LVDS1_D[1] | 49 | 48 |
| LVDS0_D[2] | 37 | 38 | | LVDS1_D[2] | 35 | 36 |
| LVDS0_D[3] | 29 | 30 | | LVDS1_D[3] | 27 | 28 |
| LVDS0_CLK  | 54 | 53 | | LVDS1_CLK  | 39 | 40 |

### Pulapka: sztywne IO_LOC dla DQ blokowaly rozmieszczenie

Przy recznie przypisanych wszystkich 32 pinach DQ PnR nie potrafil znalezc
10 wolnych par TLVDS (`PR0003: Failed to place with 3 IOBUF(s) unPlaced`).
Test w izolacji pokazal, ze **samych par LVDS miesci sie co najmniej 12** -
problem byl wiec kolizja o konkretne piny, nie brakiem zasobow.

Rozwiazanie: zdjac `IO_LOC` z DQ i zostawic narzedziu dobor. Po udanym PnR
odczytac przydzielone pary z `impl/pnr/usb_gpif.pin.html` i utrwalic je w
`.cst`. **Pinout dla PCB nalezy generowac tak, a nie wymyslac recznie.**

Nadal placeholder: brak serializacji OSER10/gearbox i timingu wideo. Test
dowodzi, ze **piny i pary sa dostepne**, nie ze tor osiagnie 1039 Mbit/s.

## Fmax spada wraz z dokladaniem logiki

| Etap | Fmax | Zapas nad 100 MHz |
|---|---:|---:|
| sam odbiornik GPIF | 148.9 MHz | 49% |
| + checker bring-up | 111.2 MHz | 11% |
| + placeholdery LVDS | 104.9 MHz | 5% |

Zapas topnieje szybko. Dekoder MJPEG i prawdziwy nadajnik LVDS beda musialy
albo trafic na wlasna, wolniejsza domene zegarowa, albo zostac potokowane.
Do tego dochodzi nierozwiazane ostrzezenie `PR1014` o rejestrze negedge na
zwyklym routingu.


---

# I2C EDID na pinach po diodach (2026-08-28)

Diody bring-up (`led_stream_ok`, `led_error`) to sygnaly tymczasowe - w wersji
produkcyjnej ich nie bedzie. Ich piny przejmuje **I2C do odczytu EDID**
z wyswietlaczy, wiec nie powiekszaja docelowego budzetu.

```
I/O Port : 61   (32 DQ + 4 GPIF + 20 LVDS + clk + reset + 2 I2C + 2 LED)
Inout Buf: 2    <- obie linie I2C faktycznie dwukierunkowe
Bitstream: OK,  Setup/Hold violated: 0 / 0
Fmax: 111.577 MHz przy wymaganych 100
Symulacja: PASS (4096/4096)
```

Piny I2C: **SCL=57, SDA=63**, `IO_TYPE=LVCMOS33 PULL_MODE=UP OPEN_DRAIN=ON`.

**Pulapka:** placeholder I2C napisany jako `assign X = warunek ? 1'bz : 1'b0`
bez odczytu linii zostaje przez synteze zwiniety do zwyklego wyjscia
(`Inout Buf = 0` w raporcie) - test zajmowalby pin, ale nie sprawdzalby
dwukierunkowosci. Odczyt musi wchodzic do logiki sterujacej `oe`.

## Twardy limit pinow (zmierzony)

Komunikat narzedzia przy przekroczeniu:
```
The number(67) of ports exceeds the resource limit 61 regular I/Os and 1 RECONFIG_N
```
Czyli **62 piny lacznie** przy MSPI+SSPI oddanych na GPIO i zachowanym JTAG.
Przy 61 uzytych **zostaje 1 wolny pin** - i to licząc, ze `reset` siedzi na
RECONFIG_N (ostrzezenie `CT1122`: sygnal na tym pinie moze wywolac
przeprogramowanie ukladu - do rozwazenia przy PCB).

Realna rezerwa, gdy zabraknie: **LVDS 18bpp zamiast 24bpp** (3 pary danych na
wyswietlacz zamiast 4) zwalnia 4 piny kosztem glebi koloru.
