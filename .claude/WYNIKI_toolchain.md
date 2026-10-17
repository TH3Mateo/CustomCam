# Wyniki: bring-up toolchainu Vivado 2017.4 (2026-09-02)

Zmierzone, nie szacowane. Czesc **XC7K325T-2FFG676C** (`xc7k325tffg676-2`).
Platforma Gowin/GW2AR **porzucona** - patrz nota na koncu.

## Status: DZIALA - pelny lancuch SystemVerilog -> .bit

```
make check     OK
make simulate  PASS   (XSim, banner z testbencha)
make synth     OK     0 bledow, 0 critical warnings
make impl      OK     timing spelniony
make bit       OK     build/hello/hello_top.bit, 11 MB
make all       rc=0   od zera
```

Modul testowy `hello` celowo uzywa konstrukcji SystemVerilog z `old/usb_gpif/`.
**Wszystkie przeszly** przez synteze i XSim 2017.4:

| Konstrukcja | Gdzie w docelowym kodzie | Status |
|---|---|---|
| `package` + `import pkg::*` w naglowku modulu | `usb_gpif_rx.sv:25` | OK |
| `typedef enum logic [1:0]` + `.name()` w TB | `rd_state_t` | OK |
| `always_ff @(posedge clk)`, reset synchroniczny | wszystkie rejestry | OK |
| `$clog2` w wyrazeniu `localparam` | `FIFO_ADDR_BITS` | OK |
| `logic`, `'0`, `{N{1'b1}}` | wszedzie | OK |

To byla glowna niewiadoma przed portem - **nie ma przeszkody w przeniesieniu
`usb_gpif` w obecnej postaci skladniowej.**

## Zasoby modulu testowego (dla skali)

| Zasob | Uzycie | Dostepne | % |
|---|---:|---:|---:|
| Slice LUTs | 30 | 203 800 | 0.01 |
| Slice Registers | 33 | 407 600 | <0.01 |

Dla porownania caly `usb_gpif` na GW2AR zajmowal 257 LUT z 20 736 (2%).
Na K325T bylby ponizej 0.15%.

## Trzy zrodla FALSZYWEGO SUKCESU (najwazniejsze ustalenie)

Toolchain, ktory nie potrafi zglosic porazki, jest gorszy od braku toolchainu.
Znalezione i **zneutralizowane**:

### 1. `vivado-sh.exe` konczy sie kodem 0 mimo braku DLL
```
vivado-sh.exe: error while loading shared libraries: librdi_commonmain.dll
$? = 0
```
Uruchamiany bezposrednio nie ma PATH do `lib/win64.o` i ~25 zmiennych `RDI_*`,
ktore ustawia `loader.bat`. **Rozwiazanie: uzywamy wylacznie `bin/vivado.bat`.**
Narzut wrappera ~9 s, nieistotny wobec minut syntezy.

### 2. `$fatal` w testbenchu daje exit 0

**Zmierzone na przypadku granicznym** - testbench drukuje banner PASS,
a zaraz potem wola `$fatal(1)`:
```
xelab -R z $fatal(1)  -> rc=0
xsim --runall         -> rc=0
log zawiera:  "=== PASS: udaje ze przeszlo ==="  ORAZ  "Fatal: celowy blad"
```

**Rozwiazanie - bramka DWUSTOPNIOWA w Makefile:**
```make
@grep -qE "^Fatal:|^Error:" $(SIM_LOG) && { echo "FAIL"; exit 1; } || true
@grep -q "=== PASS" $(SIM_LOG) || { echo "FAIL (brak bannera)"; exit 1; }
```

**Obie warstwy sa konieczne** - zweryfikowane na powyzszym przypadku:
- warstwa 2 (banner) **by NIE zadzialala** - banner byl obecny mimo `$fatal`
- warstwa 1 (`Fatal:`) zlapala
- przy cichym padzie TB przed koncem jest odwrotnie

### 3. `tee` w potoku maskuje kod wyjscia

`narzedzie | tee log` zwraca kod `tee` (zawsze 0), nie narzedzia.
Rozwiazane przez `SHELL := /bin/bash` + `.SHELLFLAGS := -o pipefail -c`.

### KOREKTA wczesniejszego ustalenia

Pierwsza wersja tego dokumentu twierdzila, ze `xvlog.bat`/`xelab.bat`
**nie propaguja** kodu bledu, bo nie maja `exit /b %errorlevel%`.
**To bylo bledne.** Wolaja `loader.bat`, ktory te linie ma (2 wystapienia).

Zmierzone: `xvlog` na pliku z bledem skladni -> **rc=1**.

Nie zmienia to konstrukcji bramki - `$fatal` (punkt 2) i tak wymaga
parsowania logu, wiec dwustopniowa bramka zostaje uzasadniona.

### Czego NIE trzeba obchodzic

Wbrew czestym poradom z forow: **`vivado -mode batch` w 2017.4 zwraca
poprawne kody wyjscia** (blad Tcl, blad syntezy, blad DRC -> rc=1) i sam
przerywa skrypt. Dlatego w `.tcl` **nie ma `catch`** - owijanie krokow w
`catch` POLKNELOBY blad i zamienilo porazke w cichy sukces.

## Testy negatywne - wszystkie zaliczone

Wazniejsze od pozytywnych, bo cichy falszywy sukces jest grozniejszy
od jawnej porazki.

| Test | Oczekiwane | Wynik |
|---|---|---|
| Testbench zglasza FAIL (brak bannera PASS) | make != 0 | **rc=2** |
| Blad skladni w zrodle (`.sv` bez srednika) | make != 0 | **rc=2** |
| Nierealizowalny timing (zegar 1 GHz) | make != 0 | **rc=2** |
| Literowka w nazwie portu w `.xdc` | make != 0 | **rc=2** |

Ostatni przypadek jest podstepny: `set_property` na nieistniejacym porcie
daje tylko `CRITICAL WARNING [Common 17-55] expects at least one object`,
constraint **po cichu znika**, a pin zostaje nieprzypisany. Sam `catch`
w Tcl tego NIE lapie (`read_xdc` konczy sie sukcesem). Lapie to
`set_msg_config -severity {CRITICAL WARNING} -new_severity ERROR`
w `common.tcl`. Klasa bledu szczegolnie grozna przy pinoucie PCB.

## Bramka timingu - konieczna, bo wzorzec Xilinxa jej nie ma

`examples/Vivado_Tutorial/run_bft_kintex7_batch.tcl` zapisuje raport
timingu, ktorego **nikt nie czyta** - build z naruszeniem timingu
wyprodukowalby bitstream nie dzialajacy na sprzecie.

Dolozone w `scripts/impl.tcl`:
```tcl
set podsumowanie [report_timing_summary -no_header -no_detailed_paths -return_string]
if {![string match -nocase {*timing constraints are met*} $podsumowanie]} {
    error "TIMING NIESPELNIONY"
}
```

**Pulapka:** popularna rada `get_property SLACK [get_timing_paths ...]`
zwraca w non-project mode **pusta wartosc**, a `get_property STATS.WNS
[get_runs]` wywala `ERROR: [Common 17-161]` (brak obiektow "run" poza
project mode). Dopasowanie tekstu na `-return_string` jest jedyna
niezawodna metoda.

## Pulapka: timescale musi byc w KAZDYM pliku

```
ERROR: [XSIM 43-4099] Module hello_top doesn't have a timescale but at
least one module in design has a timescale.
```
TB mial `` `timescale ``, moduly nie. XSim tego nie toleruje. Rozwiazane
dwutorowo: dyrektywa w kazdym pliku **oraz** `-timescale 1ns/1ps` w `xelab`.

## Piny - odczytane z bazy urzadzenia, nie zgadniete

`get_package_pins` dla `xc7k325tffg676-2`. Banki HR 12-16 i 32-34, po 50
pinow kazdy. Zegar na **Y23** (`IO_L12P_T1_MRCC_12`) - pin MRCC, zdolny
napedzac globalna siec zegarowa.

To swiadome uniknięcie problemu z GW2AR, gdzie rejestr trafil na zwykly
routing (`WARN PR1014` w `WYNIKI_usb_gpif.md`) i pozostalo to nierozwiazane.

**`.xdc` jest ATRAPA** - PCB nie istnieje. Docelowy pinout ma byc
generowany przez `write_xdc -no_fixed_only` po udanym PnR (w `impl.tcl`),
zgodnie z metoda z `WYNIKI_usb_gpif.md`: *"Pinout dla PCB nalezy generowac
tak, a nie wymyslac recznie"*.

## Zasoby ukladu - korekta KINTEX7_ALTERNATYWA.md

Tamten dokument podawal liczby "z pamieci/DS180, do zweryfikowania".
Odczytane z `get_property`:

| Zasob | xc7k325t-2ffg676 | GW2AR-18 | krotnosc |
|---|---:|---:|---:|
| LUT | **203 800** | 20 736 | ~10x |
| BRAM | **445** | 46 | ~10x |
| DSP | **840** | 48 | 17x |
| I/O | **400** | 66 | 6x |

Caly budzet pinow z `PINOUT.md` ("zapas 1 pin", rezygnacja z flash)
przestaje obowiazywac.

## Licencje IP - stan do rozstrzygniecia

| IP | kintex7 | klucz |
|---|---|---|
| `displayport_v7_0` | **Discontinued** (0 wpisow Production) | `displayport@2016.04`, typ **Design_Linking** |
| `dp_tx_subsystem_v2_1` | **Production** | `dp_tx_subsystem@2017.10` - **brak w pliku licencji** |
| `vid_phy_controller_v2_1` (GTX PHY) | **Production** | **brak - darmowe** |
| `v_axi4s_vid_out_v4_0`, `vid_edid_v1_0` | - | **brak - darmowe** |

Wbudowany `data/ip/core_licenses/Xilinx.lic`: 37 wpisow, **wszystkie
`Design_Linking`** (synteza/implementacja tak, `write_bitstream` nie).
Dla kontrastu `XilinxFree.lic`: 21 wpisow, wszystkie `Bought`.

Uzytkownik ma **wlasny plik licencji** (pobrany samodzielnie, sciezka
podana Vivado recznie) - do sprawdzenia przy tescie IP.

**Nie blokuje to toolchainu ani portu `usb_gpif`** - zaden z nich nie
uzywa platnych IP, co potwierdza wygenerowany bitstream.

---

## Nota: co jest nieaktualne w pozostalych plikach .claude/

Dokumenty `PINOUT.md`, `LVDS_EDP.md`, `PLAN_usb_gpif.md` i
`KINTEX7_ALTERNATYWA.md` opisuja platforme **GW2AR-18 QN88 + toolchain
Gowin**, ktora zostala porzucona. Zostaja jako historia decyzji, ale:

- **`PINOUT.md`** - caly budzet 66 I/O nieaktualny (teraz 400)
- **`LVDS_EDP.md`** - "eDP niemozliwe bez mostka LT8911EX" dotyczylo
  ukladu bez transceiverow; K7 ma GTX
- **`KINTEX7_ALTERNATYWA.md`** - zakladal openXC7, bo "Vivado dla K325T
  wymaga platnej licencji"; uzywamy Vivado 2017.4
- **`PLAN_usb_gpif.md`** - decyzje architektoniczne (PCLK z FPGA, brak CDC,
  redukcja pinow GPIF 44->35) **pozostaja aktualne**; nieaktualne sa tylko
  liczby pinow i toolchain

---

# Licencje IP - ROZSTRZYGNIETE empirycznie (2026-09-02)

Nie analiza plikow `.lic`, tylko faktyczne uruchomienie `create_ip`,
`generate_target` i `synth_ip` na czesci `xc7k325tffg676-2`.

## Wynik

| IP | create_ip | generate | synth_ip | komunikat |
|---|---|---|---|---|
| `pcie_7x` | **OK** | - | - | bez zastrzezen |
| `vid_phy_controller` (GTX PHY) | **OK** | - | - | bez zastrzezen |
| `dp_tx_subsystem` | OK* | **OK** | **OK** | *ostrzezenie o braku licencji |

Komunikat dla `dp_tx_subsystem` (powtarzany na kazdym etapie):
```
IP 'g_dptx' requires one or more mandatory licenses but no valid licenses
were found. However license checkpoints may prevent use of this IP in some
tool flows.
```

## Co to praktycznie znaczy

**DP IP da sie wygenerowac I ZSYNTEZOWAC bez licencji.** Blokada przychodzi
dopiero przy `write_bitstream` - zgodne z typem `Design_Linking` we wbudowanym
`core_licenses/Xilinx.lic`.

| Czynnosc | Bez licencji DP |
|---|---|
| Zaprojektowanie toru eDP | **mozliwe** |
| Zmierzenie zasobow (LUT/BRAM/GTX) | **mozliwe** |
| Weryfikacja timingu | **mozliwe** |
| **Zaprogramowanie ukladu** | **NIE** |

Czyli mozna przejsc caly etap projektowy i dowiedziec sie, czy tor eDP
w ogole miesci sie w ukladzie - a decyzje o zakupie licencji podjac
na podstawie zmierzonych liczb, a nie zgadywania. To dobra kolejnosc.

## Uwaga metodologiczna

`get_license_status` **nie istnieje** w Vivado 2017.4 (`info commands
*licens*` zwraca pusta liste). Jedyny sposob sprawdzenia licencji IP to
faktyczna proba uzycia i obserwacja komunikatow.

---

# GTX: 10.3 Gb/s na linie, nie 6.6 (zmierzone 2026-09-02)

## Obalone zalozenie z KINTEX7_ALTERNATYWA.md

Tamten dokument (sekcja "GTX - to jest wlasciwy zysk") podawal za DS182
Tabela 56:
> FGTXMAX, FFG900, -2 = **6.6** Gb/s

i na tej podstawie odrzucal USB 10 Gbps oraz ograniczal opcje eDP.
**Limit 6.6 Gb/s dotyczy obudow FBG (wire-bond), nie FF/FFG (flip-chip).**
Nasz uklad to **FFG676**.

## Pomiar

Metoda: `create_ip gtwizard 3.6` dla `xc7k325tffg676-2`, ustawianie
`CONFIG.identical_val_tx_line_rate` i sprawdzanie, czy narzedzie przyjmuje.

| Line rate [Gb/s] | Wynik |
|---:|---|
| 5.0 | przyjete |
| 6.6 | przyjete |
| 8.0 | **przyjete** |
| **10.3125** | **przyjete** |
| 12.5 | odrzucone |
| 13.0 | odrzucone |

**Potwierdzone SYNTEZA**, nie tylko konfiguracja GUI:
```
generate_target synthesis + synth_ip @ 10.3125 Gb/s -> OK
```

Uwaga metodologiczna: `gt0_val_*_line_rate` jest parametrem **zablokowanym** -
zmiana jest cicho ignorowana (`WARNING [IP_Flow 19-3374] ... has been
ignored`). Sterowac trzeba przez `identical_val_*`. Ustawianie kilku
parametrow jednym `set_property -dict` zawodzi - trzeba pojedynczo.

## Co to otwiera

| Zastosowanie | Wymagane [Gb/s/linia] | Status na FFG676 |
|---|---:|---|
| eDP RBR | 1.62 | OK |
| eDP HBR | 2.7 | OK |
| **eDP HBR2** | **5.4** | **OK** |
| USB 3.0 SuperSpeed | 5.0 | OK (elektrycznie) |
| **USB 3.1 Gen2** | **10.0** | **OK (elektrycznie)** |

Przy 16 kanalach GTXE2 - patrz zasoby nizej - warstwa fizyczna przestaje
byc ograniczeniem projektu. Waskim gardlem jest teraz **protokol i jego
implementacja**, nie krzem.

**Zastrzezenie:** to jest limit ELEKTRYCZNY transceivera potwierdzony przez
narzedzie. Nie oznacza, ze USB 3.1 Gen2 zadziala - do tego potrzebny jest
caly stack protokolu (LFPS, link training, LTSSM), ktorego nie mamy.

## Zasoby transceiverow XC7K325T-2FFG676 (z get_sites)

| Zasob | Liczba |
|---|---:|
| GTXE2_CHANNEL | **16** |
| GTXE2_COMMON (QPLL) | 4 |
| Twardy blok PCIe | 1 (PCIE_X0Y0) |
| MMCME2_ADV / PLLE2_ADV | 10 / 10 |
| BUFGCTRL | 32 |

16 kanalow x 10.3 Gb/s = ~165 Gb/s surowej przepustowosci transceiverow.

---

# Licencja dp_tx_subsystem POZYSKANA (2026-09-02)

Uzytkownik zdobyl licencje. Zweryfikowane empirycznie - ostrzezenie
```
IP requires one or more mandatory licenses but no valid licenses were found
```
**zniknelo calkowicie** (wczesniej pojawialo sie 3x przy tej samej operacji).
`create_ip` -> `generate_target` -> `synth_ip` przechodzi czysto.

## Mozliwosci dp_tx_subsystem v2.1 (odczytane z IP)

| Parametr | Wartosc domyslna | Uwagi |
|---|---|---|
| `LANE_COUNT` | 4 | liczba linii DP |
| `MODE` | 0 = SST | **1 = MST** (Multi-Stream Transport) |
| `NUM_STREAMS` | 1 | przy MST: wiele monitorow jednym zlaczem |
| `BITS_PER_COLOR` | 8 | 24 bpp |
| `PIXEL_MODE` | 4 | pikseli na takt |
| `PHY_type_External` | 1 | PHY zewnetrzny (vid_phy_controller/GTX) |
| `HDCP_ENABLE` / `AUDIO_ENABLE` | 0 | wylaczone |

## MST 4 strumienie - ZSYNTEZOWANE

```
MODE=1 (MST), NUM_STREAMS=4, LANE_COUNT=4
generate_target synthesis + synth_ip -> OK
```

**To bezposrednio odpowiada na cel "3+ monitory":** jedno zlacze DP moze
obsluzyc 4 monitory przez MST, zamiast czterech osobnych torow. Radykalnie
upraszcza plyte wzgledem koncepcji "N x osobny tor LVDS/eDP".

Do policzenia przy projektowaniu: 4 linie x 5.4 Gb/s (HBR2) = 21.6 Gb/s
surowo, ~17.3 Gb/s po 8b/10b. To dzielone miedzy wszystkie strumienie MST.
3x 1080p60 24bpp = 10.7 Gb/s - **miesci sie**.

---

# USB: research zakonczony - wniosek jest niewygodny

## Twarda konkluzja: zmiana mostka NIE DA wiecej pasma

Wszystkie realne opcje USB 3.0 Gen1 lezą w przedziale **320-400 MB/s**,
bo to fizyczny sufit 5 Gb/s po 8b/10b (=500 MB/s) minus narzut protokolu.
**Obecny FX3 juz jest blisko tego sufitu.**

| Opcja | Pasmo | Ryzyko | Koszt prototypu |
|---|---:|---|---|
| **XillyUSB na GTX** | 400 MB/s | niskie-srednie | ~75 EUR adapter, IP darmowy do ewaluacji |
| Obecny FX3 | ~320-400 MB/s | znane, dziala | 0 |
| FTDI FT601 | 346-374 MB/s | niskie, timing I/O uciazliwy | ~$9/chip |
| Wlasny stos na GTX | >320 MB/s | **wysokie** | analizator protokolu ~$50k |
| usb3_pipe | nieznane | **bardzo wysokie** | rdzen w przebudowie |

## Co to znaczy dla projektu

**FX3 zostaje uzasadniony.** Nie ma sensu go wymieniac dla pasma - trzeba
by isc w USB 3.1 Gen2 (10 Gb/s), a dla tego **nie istnieje zadne IP device
na GTX 7-series**. To byl by projekt badawczy od zera.

Wniosek: **pasmo USB (~3.2 Gb/s) jest twardym ograniczeniem projektu.**
Cel "3+ monitory" musi byc osiagniety przez KOMPRESJE, nie przez szersze
wejscie. 3x 1080p60 = 10.7 Gb/s surowo, wiec wymagany stopien >= 3.4x.
MJPEG (10-20x) daje to z zapasem.

## Dowod, ze GTX jako USB PHY dziala na NASZYM ukladzie

arXiv:2301.11505 (IHEP, Chinska Akademia Nauk, 2023):
"Design of an FPGA-based USB 3.0 device controller"
- uklad docelowy: **Kintex-7 325t** - dokladnie nasz
- transceiver FPGA jako USB PHY, **bez zewnetrznego chipa**
- zmierzone: **>320 MB/s** bulk-in i bulk-out
- zuzycie: **4.59% slice'ow**
- LFPS: osobny modul nadaje LFPS gdy **GTX wylaczone**, SIE komunikuje
  gdy wlaczone

## Stanowisko AMD vs praktyka - sprzeczne, ale rozstrzygalne

AMD: transceivery 7-series "sa elektrycznie kompatybilne z USB, ale nie
byly testowane wewnetrznie i **nie sa oficjalnie wspierane**".
Praktyka: XillyUSB (produkt komercyjny), praca IHEP i usb3_pipe - wszystkie
dzialaja na GTX.

Rozstrzygniecie: **dziala, ale bez supportu AMD.** To ryzyko biznesowe,
nie techniczna niemozliwosc.

## usb3_pipe - NIE nadaje sie na podstawe produktu

- zyje (ostatni commit 2026-01-02), ale commity to `Rewrite usb3_link.v WiP`,
  `Rewrite usb3_ep WiP` - **warstwa protokolu w trakcie przebudowy**
- README: *"Enumeration has only been done on a few hardware setups and there
  is still work in progress to improve reliability"*
- **brak JAKIEGOKOLWIEK raportu przepustowosci ze sprzetu** w issues
- otwarte issue #34: blad kompilacji w Vivado, bez odpowiedzi

## XillyUSB - realna opcja, gdyby chciec usunac FX3 z plyty

- GTX jako PHY bezposrednio, **400 MB/s**, gotowy bundle dla KC705 (Kintex-7)
- **darmowy do ewaluacji, w tym wbudowania w projekt i testow polowych**;
  25-85k EUR dopiero przy sprzedazy komercyjnej
- usuwa z plyty: FX3, firmware ARM9, 40+ pinow GPIF
- **ograniczenie: brak fallbacku do USB 2.0** - na porcie USB 2.0 urzadzenie
  nie zadziala wcale, bez komunikatu

## Errata FX3 warta odnotowania

Blad: "errors in payload data towards the host" gdy pakiet zerowej dlugosci
poprzedza dane w ciagu 125 us. **Bez planowanej poprawki.** Do sprawdzenia,
czy nasz przeplyw tego dotyka.

---

# Zasoby dp_tx_subsystem - ZMIERZONE (2026-09-02)

Metoda: `create_ip` -> `synth_ip` -> `open_checkpoint` -> `report_utilization`.
Liczby z checkpointu IP, nie szacunki.

| Wariant | LUT | Rejestry | BRAM | DSP |
|---|---:|---:|---:|---:|
| **SST** (1 monitor, 4 linie) | 8 576 | 10 824 | 5.5 | 0 |
| **MST 4 strumienie** (4 linie) | **31 518** | 36 573 | **44** | 0 |
| Dostepne w XC7K325T | 203 800 | 407 600 | 445 | 840 |
| **MST jako % ukladu** | **15.5%** | 9.0% | **9.9%** | 0% |

## Budzet po odjeciu toru eDP

```
Uklad                     203 800 LUT   445 BRAM
- dp_tx_subsystem MST 4x   -31 518       -44
- usb_gpif (port z Gowin)     ~300        ~1   (bylo 257 LUT / 1 BSRAM)
                          -----------   -------
ZOSTAJE na dekoder MJPEG   ~172 000      ~400
                            (84%)         (90%)
```

**To jest odpowiedz na pytanie "czy calosc sie zmiesci".** Na GW2AR-18
(20 736 LUT) sam dp_tx_subsystem MST **nie zmiescilby sie w ogole** -
potrzebuje 1.5x calego tamtego ukladu. Na K325T zostaje 84% na dekoder.

Uwaga: DSP = 0 w obu wariantach. Cale 840 DSP zostaje na dekoder MJPEG
(IDCT to glowny konsument DSP) - to bardzo korzystne.

---

# Pulapka: przejsciowy blad odczytu plikow instalacji Vivado

Zaobserwowane raz podczas rownoleglej pracy (build + testy IP):
```
couldn't read file "C:/Xilinx/Vivado/2017.4/scripts/rt/data/unimacro/
unimacro_vhdl.tcl": No error
synth_design failed
```
Plik **istnieje i jest normalnie czytelny** - sprawdzone bezposrednio.
Powtorzenie `make all` przeszlo bez zmian w kodzie.

Prawdopodobna przyczyna: chwilowa blokada pliku (antywirus skanujacy
instalacje albo kolizja miedzy rownolegle uruchomionymi procesami Vivado).

**Wniosek praktyczny:** przy takim bledzie NIE szukac problemu w swoim
kodzie - najpierw powtorzyc build. Nie uruchamiac kilku instancji Vivado
rownolegle na tej samej instalacji.

---

# KOREKTA: MST nie nadaje sie do surowych matryc eDP (2026-09-02)

## Blad w poprzedniej sekcji

Zapisalem, ze MST (`MODE=1`, `NUM_STREAMS=4`) "obsluzy 4 monitory jednym
zlaczem". **To bylo bledne dla naszego zastosowania.**

MST to funkcja **hosta / hubu DisplayPort**: strumienie ida jednym kablem DP
do monitora z wejsciem DP, ktory ma wlasny odbiornik MST i rozdziela je dalej.

**Nasze wyswietlacze to SUROWE MATRYCE eDP na zlaczach 30-pin.** Matryca:
- nie ma odbiornika MST ani logiki rozdzielajacej strumienie
- oczekuje **wlasnych linii** i wlasnego link training po AUX
- jest koncowka toru, nie hubem

Na PCB maja byc **osobne zlacza 30-pin**, wiec kazde potrzebuje
**niezaleznego toru eDP**.

## Poprawna architektura: N x niezalezny dp_tx_subsystem (SST)

Zmierzone dla jednego toru eDP (SST, 2 linie - typowe dla 1080p):

| | LUT | Rejestry | BRAM | GTX |
|---|---:|---:|---:|---:|
| **1 tor eDP** (SST, 2 linie) | 6 046 | 8 809 | 3 | 2 |
| **3 tory** (3 matryce) | **18 138** | 26 427 | 9 | **6** |
| % ukladu | **8.9%** | 6.5% | 2.0% | - |

**Wychodzi TANIEJ niz bledny wariant MST** (31 518 LUT), bo MST niesie
narzut logiki rozdzielania strumieni, ktorej tu nie potrzebujemy.

Przepustowosc jednego toru: 2 linie x 2.7 Gb/s (HBR) = 5.4 Gb/s surowo,
**4.32 Gb/s po 8b/10b**. 1080p60 24bpp = 3.56 Gb/s -> miesci sie z zapasem
21%. Przy HBR2 (5.4 Gb/s/linia) zapas rosnie dwukrotnie.

## KRYTYCZNE DLA PCB: tylko 8 kanalow GTX w FFG676

Wczesniej zapisalem "16x GTXE2_CHANNEL" - to liczba kanalow w KRZEMIE.
**W obudowie FFG676 wyprowadzone sa tylko 2 banki MGT = 8 kanalow.**
Pozostale 8 nie ma kulek.

```
Kanalow TX z wyprowadzonymi pinami: 8   (zmierzone: get_package_pins PIN_FUNC =~ *MGTXTXP*)
```

### Mapa pinow MGT - do schematu PCB

**BANK 115** (quad, wlasny QPLL):
| Kanal | TX+ | TX- |
|---|---|---|
| 0 | P2 | P1 |
| 1 | M2 | M1 |
| 2 | K2 | K1 |
| 3 | H2 | H1 |

refclk0: H6/H5 (P/N), refclk1: K6/K5 (P/N)

**BANK 116** (quad, wlasny QPLL):
| Kanal | TX+ | TX- |
|---|---|---|
| 0 | F2 | F1 |
| 1 | D2 | D1 |
| 2 | B2 | B1 |
| 3 | A4 | A3 |

refclk0: D6/D5 (P/N), refclk1: F6/F5 (P/N)

Piny RX (MGTXRXP/N) tez sa wyprowadzone - dla eDP TX nieuzywane,
ale AUX to osobny kanal dwukierunkowy na zwyklych I/O, nie na GTX.

### Budzet GTX dla 3 matryc

```
Dostepne kanaly GTX (FFG676)            8
- 3 matryce eDP x 2 linie              -6
                                       ---
ZOSTAJE                                 2
```

**Miesci sie, ale zapas to 2 kanaly.** Warianty:
- **3 matryce x 2 linie = 6 kanalow** -> zostaja 2 (np. na USB3 przez GTX)
- 3 matryce x 4 linie = 12 kanalow -> **NIE MIESCI SIE**
- 4 matryce x 2 linie = 8 kanalow -> miesci sie, ale zero zapasu

**Wniosek: przy 3 matrycach trzymamy sie 2 linii eDP na matryce.**
Jesli potrzebne beda 4 linie na matryce (wyzsza rozdzielczosc), limitem
staje sie obudowa - nie logika.

### Uwaga o refclk i quadach

Kazdy bank ma **wlasny QPLL i wlasne piny refclk**. Rozmieszczenie torow
miedzy bankami wplywa na to, ile zrodel zegara trzeba na PCB. Kanaly
w jednym quadzie moga dzielic refclk - czyli 3 tory rozlozone jako
4+2 albo 2+4 miedzy banki 115/116 wymagaja **2 zrodel refclk**, nie 3.

To do uzgodnienia przy schemacie: rozklad 3 torow na 2 quady.

---

# KRYTYCZNE: vid_phy_controller rezerwuje CALY quad GTX (2026-09-02)

## Odkrycie

Skonfigurowano `vid_phy_controller` na `C_Tx_No_Of_Channels=2` (bo eDP HBR
potrzebuje tylko 2 linii), oczekujac zuzycia 2 z 8 dostepnych kanalow.

**Zmierzone w raporcie zasobow po syntezie:**
```
GTXE2_COMMON    1 z 2   (50%)
GTXE2_CHANNEL   4 z 8   (50%)   <- NIE 2, jak sugerowalby C_Tx_No_Of_Channels
```

Potwierdzone niezaleznie: `CONFIG.CHANNEL_ENABLE = X0Y0 X0Y1 X0Y2 X0Y3` -
**caly quad**, nie podzbior kanalow. `C_Tx_No_Of_Channels=2` steruje tym,
ile z 4 zarezerwowanych kanalow jest AKTYWNIE uzywanych logicznie -
nie zwalnia pozostalych dla innej instancji.

**Sprawdzone: IP nie ma parametru "niezalezne strumienie w jednym quadzie".**
`vid_phy_controller` to kontroler JEDNEGO linku wideo na quad, nie
multiplekser wielu niezaleznych sesji DP. Trzy niezalezne matryce eDP
= trzy niezalezne instancje = **trzy quady**, niezaleznie od tego, ze
kazda uzywa logicznie tylko 2 z 4 kanalow fizycznych w quadzie.

## Poprawiony budzet GTX dla FFG676

```
Dostepne QUADY w obudowie FFG676         2   (banki MGT 115, 116)
Dostepne kanaly GTX                      8   (2 quady x 4)

Kazdy tor eDP (vid_phy_controller)       1 QUAD (4 kanaly), 
                                          niezaleznie od C_Tx_No_Of_Channels
                                       ------
MAKSYMALNIE torow eDP na FFG676:         2
```

**TO JEST PROBLEM: 3 matryce eDP NIE MIESZCZA SIE w FFG676 przez
osobne instancje vid_phy_controller.** Zmieszcza sie tylko 2.

## Do rozstrzygniecia - trzy sciezki

1. **Sprawdzic, czy jedna instancja vid_phy_controller z 4 kanalami da sie
   podzielic na 2 NIEZALEZNE pary linii w RTL** (nie przez parametry IP,
   tylko recznym poprowadzeniem AXI4-Stream do dwoch roznych `dp_tx_subsystem`
   z dwoch par kanalow tego samego quadu). Do zweryfikowania w dokumentacji
   PG (nie ma jej lokalnie - trzeba pobrac PG133) i/lub eksperymentalnie:
   czy TX_DATA/TX_CLK per-kanal sa niezalezne, czy caly quad dzieli jeden
   zegar liniowy (jesli tak - matryce musialyby pracowac na tym samym
   line rate, co dla eDP jest akceptowalne, bo to i tak zwykle ten sam typ
   panelu).

2. **Wieksza obudowa.** FFG900 ma wiecej wyprowadzonych bankow MGT (do
   sprawdzenia ile dokladnie) - ale to zmiana BGA i calego PCB, nie tylko
   ustawien IP.

3. **Nie uzywac vid_phy_controller jako calosci** - napisac wlasna,
   cienszą warstwe PHY na `GTXE2_CHANNEL` bezposrednio (bez wrappera IP),
   sterujac kazdym z 4 kanalow quadu niezaleznie. Vid_phy_controller to
   wygodny wrapper, nie jedyna droga do GTX - `GTXE2_CHANNEL` per-kanal
   jest adresowalny osobno w prymitywie. Wiecej pracy, ale odzyskuje
   pelne wykorzystanie kanalow.

**Nie podejmowac decyzji architektonicznej bez sprawdzenia opcji 1** -
to najtansza droga, jesli dokumentacja PG133 potwierdzi niezaleznosc
kanalow w obrebie quadu dla roznych sesji DP.

---

# Port usb_gpif na Kintex-7 - symulacja PASS (2026-09-02)

## Co przeniesiono

| Plik | Zmiana |
|---|---|
| `usb_gpif_pkg.sv` | bez zmian funkcjonalnych (dodany `timescale`) |
| `usb_gpif_fifo.sv` | bez zmian - inferencja pamieci, nie zalezy od vendora |
| `usb_gpif.sv` | dodany parametr `IDELAY_TAPS` przekazywany do `_rx` |
| **`usb_gpif_rx.sv`** | **przepisany: negedge -> IDELAYE2** (patrz nizej) |
| `usb_gpif_dev.sv` | dodany `IDELAYCTRL` (kalibrator, 1x na bank) + `idelay_refclk`; **usuniete placeholdery LVDS/EDID** - nieaktualne na K7 (eDP idzie przez GTX, nie GPIO) |
| `usb_gpif_dev_tb.sv` | model FX3 bez zmian; dodana obsluga `idelay_refclk` i sekwencji resetu |

## Kluczowa zmiana: negedge -> IDELAYE2

Wersja Gowin probkowala DQ na zboczu opadajacym (pol okresu = 5 ns marginesu
przy budzecie round-trip 0 ns na posedge - patrz `.claude/WYNIKI_usb_gpif.md`).
To dzialalo, ale zmierzone ostrzezenie (WARN PR1014) pokazywalo rejestr
negedge na zwyklym routingu zamiast sieci zegarowej - nierozwiazane ryzyko.

K7 ma IDELAYE2: kalibrowane opoznienie linii wejsciowej, przesuwa dane w
FAZIE (nie w cyklach) tak, zeby trafily w okno setup/hold na POSEDGE.
32 instancje (1 na bit DQ) + 1 IDELAYCTRL (kalibrator, wspolny dla banku,
NA POZIOMIE TOPU - nie w `usb_gpif_rx`, zeby nie kalibrowac tego samego
banku wielokrotnie).

Konsekwencja w potoku: **RD_LATENCY spada z 2 na 1** - jeden rejestr
(posedge) zamiast dwoch (negedge+posedge).

## Blad znaleziony i naprawiony PRZEZ TEN TEST: deadlock reset/RDY

Pierwsza wersja testbencha czekala na `idelayctrl_rdy` PRZED zwolnieniem
sygnalu `reset`, ktory jest jednoczesnie `RST` dla `IDELAYCTRL`. Skutek:
`IDELAYCTRL` nigdy nie wyszedl z resetu, `RDY` nigdy sie nie podnioslo,
test wisial w `wait()` do timeoutu (2 ms).

```
Zmierzone (sonda na portach IDELAYCTRL @ 50 us):
  RST_in=1  REFCLK=biegnie  RDY=0
```

**Naprawa:** zewnetrzny `reset` zwalniany od razu (jak POR na sprzecie);
to WEWNETRZNY `reset_sync = reset || !idelayctrl_rdy` w `usb_gpif_dev`
trzyma rdzen w resecie, dopoki kalibracja nie jest gotowa - a nie
testbench, ktory nie powinien znac szczegolow implementacji DUT.

**Wniosek na przyszlosc (analogiczny do wpisu o FLAG_EMPTY w
`WYNIKI_usb_gpif.md`):** sygnal resetu zewnetrznego i "gotowosc wewnetrzna"
to DWIE ROZNE rzeczy. Nigdy nie uzalezniac zwolnienia zewnetrznego resetu
od sygnalu, ktory sam wymaga wyjscia z tego resetu, zeby powstac.

## Wynik symulacji

```
IDELAYCTRL RDY @ 105 ns
Przeslano slow przez FX3       : 4096
Slow zaliczonych przez checker : 4096
led_error                      : 0
=== PASS: wszystkie testy zaliczone ===
```

Ten sam wynik (4096/4096, 0 bledow) co na Gowin - model FX3 (tCO=7ns,
tCFLG=8ns, przerwy DMA) jest identyczny, bo te wlasciwosci naleza do FX3,
nie do sposobu probkowania po stronie FPGA.

## Do zrobienia przed synteza na sprzecie

- **Zweryfikowac czestotliwosc `idelay_refclk`** (200 MHz +-10 MHz wg pamieci
  o UG471 - NIE zweryfikowane lokalnie, oznaczone jawnie w kodzie jako "do
  sprawdzenia przed synteza")
- **Skalibrowac `IDELAY_TAPS`** na rzeczywistym sprzecie (parametr jawny,
  wartosc startowa = srodek zakresu 0-31)
- Synteza + PnR na `xc7k325tffg676-2`, pomiar zasobow i timingu (analogicznie
  do pomiarow zrobionych dla `hello` i `dp_tx_subsystem`)

---

# Interfejs dp_tx_subsystem - zmierzony (2026-09-02)

Zbadany dla ustalenia granicy modulu `edp/` w torze
`usb_gpif -> dekoder MJPEG -> edp`.

## Wejscie wideo (od dekodera)

AXI4-Stream, jeden strumien (SST):
```
s_axis_video_stream1_tdata[47:0]   - 48 bitow
s_axis_video_stream1_tvalid/tlast/tuser
s_axis_video_stream1_tready
s_axis_aclk_stream1 / s_axis_aresetn_stream1  - wlasna domena zegara wideo
tx_vid_clk_stream1 / tx_vid_rst_stream1
```
48 bitow przy `PIXEL_MODE=4` (4 piksele/takt), `BITS_PER_COLOR=8` - dokladne
mapowanie bitow na komponenty RGB/piksele DO USTALENIA przy integracji
z dekoderem MJPEG (PG199, sekcja Video Interface) - nie zgadywac teraz,
zanim dekoder nie okresli wlasnego formatu wyjsciowego.

## Wyjscie do PHY (do GTX)

AXI4-Stream, per-lane:
```
m_axis_lnk_tx_lane0_tdata / tvalid / tready / tuser[11:0]
m_axis_lnk_tx_lane1_tdata / tvalid / tready / tuser[11:0]
tx_lnk_clk                                    - zegar linku (z PHY)
```

## AUX (link training, dwukierunkowy)

```
aux_tx_io_p / aux_tx_io_n   - INOUT, para rozniciowa, NIE na GTX (zwykle I/O)
```

## Wniosek dla granicy modulu `edp/`

Modul `edp` przyjmuje **zdekompresowany strumien pikseli** (AXI4-Stream video)
z dekodera MJPEG - NIE surowy JPEG. Kompresja/dekompresja jest w calosci
poza tym modulem. `edp` odpowiada wylacznie za: `dp_tx_subsystem` (protokol
DP/eDP) + warstwe fizyczna GTX (PHY, docelowo Shared Logic na quadzie -
patrz sekcja "vid_phy_controller rezerwuje caly quad" wyzej) + AUX na
zwyklych I/O.

---

# UWAGA ARCHITEKTONICZNA: dp_tx_subsystem wymaga AXI4-Lite (2026-09-02)

## Odkrycie

Pelna lista portow `dp_tx_subsystem` pokazuje **interfejs AXI4-Lite**
(`s_axi_*`, adres 19-bit = przestrzen 0-0x7FFFF) obok strumienia danych.

**Dwie NIEZALEZNE sciezki, nie jedna:**

| Sciezka | Porty | Kiedy aktywna |
|---|---|---|
| Dane wideo | `s_axis_video_stream1_t*` -> `m_axis_lnk_tx_lane*` | caly czas, pelna przepustowosc, sprzetowy potok w IP |
| Sterowanie | `s_axi_*` (AXI4-Lite) | rzadko - konfiguracja startowa, link training, status |

**Piksele NIGDY nie przechodza przez AXI-Lite ani przez ewentualny
procesor sterujacy.** To rozstrzyga watpliwosc uzytkownika: softcore
(gdyby byl uzyty) nie jest w torze danych, nie zjada przepustowosci.

## Problem: typowy wzorzec Xilinxa dla AXI-Lite to procesor + driver C

PG199 zaklada zwykle MicroBlaze/Zynq PS + driver `xdptxss`
(`Xilinx/embeddedsw`) realizujacy w C: link training (CR/EQ), odczyt/zapis
DPCD przez AUX, MSA. To jest utrudnienie architektoniczne - caly reszty
projektu jest czystym RTL (patrz konwencje z `.claude/PLAN_usb_gpif.md`),
a to wprowadzaloby drugi jezyk i drugi toolchain (SDK/Vitis obok Vivado).

**Do rozstrzygniecia (w toku, agent research):**
- czy dp_tx_subsystem ma tryb "polled"/rejestrowy bez procesora
- koszt zasobowy minimalnego MicroBlaze do tego JEDNEGO zadania
- czy istnieje precedens wlasnego RTL AXI-Lite master + wlasny link training
- czy starszy `displayport_v7_0` (mamy lokalnie, Discontinued dla naszej
  rodziny) ma prostszy interfejs bez AXI-Lite

Decyzja wplywa na CALA architekture modulu `edp/` - 3 niezalezne tory
oznaczaja 3 niezalezne bloki AXI-Lite do wysterowania (per matryca wlasny
link training, bo to nie MST).

---

# Decyzja: MicroBlaze + xdptxss (2026-09-02)

Uzytkownik zdecydowal: **MicroBlaze + oficjalny driver Xilinxa**, nie
wlasny RTL link training. Uzasadnienie z researchu (potwierdzone
niezaleznie): `dp_tx_subsystem` NIE MA trybu bezprocesorowego - nawet
starszy `displayport_v7_0` (PG064) tez wymaga AXI4-Lite. Koszt MicroBlaze
w konfiguracji minimalnej: ~637 LUT (0.3% ukladu, UG984, XC7K325T-3),
piksele go nie dotykaja (osobna sciezka danych vs sterowania - potwierdzone
w sekcji "UWAGA ARCHITEKTONICZNA" wyzej).

## Toolchain firmware - JEST LOKALNIE, nic do pobierania

```
C:/Xilinx/SDK/2017.4/                                    <- pelne SDK 2017.4
C:/Xilinx/SDK/2017.4/data/embeddedsw/.../dptxss_v5_0/     <- driver, LOKALNIE
```

**Driver `dptxss_v5_0`** (nowszy niz `dp_tx_subsystem_v2_1` w Vivado -
numeracja driverow i IP nie jest 1:1, ale to ten sam rodzinowo interfejs
AXI-Lite/DPCD, do zweryfikowania przy integracji czy `.h` sie zgadza z
mapa rejestrow naszej wersji IP).

**Kluczowe API** (`xdptxss.h`) - to, czego potrzebujemy, bez HDCP/RX:
```c
XDpTxSs_CfgInitialize()   // inicjalizacja z auto-generowanego xparameters.h
XDpTxSs_SetLinkRate()     // RBR/HBR/HBR2
XDpTxSs_SetLaneCount()    // 2 (nasza decyzja - patrz edp_pkg.sv)
XDpTxSs_Start()           // uruchamia link training (CR/EQ) wewnetrznie
XDpTxSs_IsConnected()     // HPD
XDpTxSs_CheckLinkStatus() // po treningu
```

**Przyklad referencyjny dla WLASNIE NASZEJ platformy:**
`examples/src/kc/xdptxss_kc705.c` (4669 linii) - **KC705 = plyta
Kintex-7**, uzywa `dppt_vid_phy_config.c` (integracja z vid_phy_controller).
To jest demo TX+RX+HDCP na plycie ewaluacyjnej - znacznie szersze niz
nasza potrzeba (tylko TX, bez RX, bez HDCP, 3x zamiast 1x). Sluzy jako
WZORZEC integracji, nie do wklejenia wprost.

**Rdzen driver bez przykladu demo:** `src/xdptxss.c` (2129 linii) + naglowki -
to jest API do wywolywania z WLASNEGO, minimalnego firmware (rzedu
~150-200 linii dla naszego zastosowania: 3x inicjalizacja + link training,
bez HDCP/RX/menu interaktywnego z demo KC705).

## Konsekwencja dla struktury projektu

Modul `edp/` bedzie MIESZANY - RTL (Vivado) + firmware C (SDK/Vitis).
To pierwszy taki modul w projekcie; `usb_gpif` jest czystym RTL.
Struktura katalogow do przemyslenia osobno od czystych modulow RTL
(np. `edp/fw/` na firmware, osobny biezacy przeplyw budowania - `.elf`
trzeba wbudowac w bitstream przez `updatemem`/BMM, narzedzie ktore juz
widzielismy w `bin/` Vivado).

---

# Architektura PHY dla 3 torow eDP - ustalona (2026-09-02)

## Zmierzone: vid_phy_controller NIE dziala w Block Design (IPI)

`create_bd_cell` dla `vid_phy_controller:2.1` przechodzi bez bledu, ale
**`gtwizard:3.6` jest ODRZUCANY przez BD**:
```
ERROR: [BD 5-313] Found unsupported IP 'xilinx.com:ip:gtwizard:3.6' in design.
```
`gtwizard` dziala TYLKO w non-project mode (`create_ip` poza BD).

## Zmierzone: gtwizard MA mechanizm Shared Logic

```tcl
CONFIG.gt0_usesharedlogic = 0 lub 1   (binarne, nie lista opcji)
```
Potwierdza to, co ustalil wczesniejszy research (wzorzec z watku Xilinx
Forums o dzieleniu quadu miedzy 2 instancje Aurora): `=0` generuje pelna
logike wspoldzielona (w tym GTXE2_COMMON), `=1` zaklada, ze jest ona
dostarczona z zewnatrz - druga instancja w parze.

## Wynikajaca architektura modulu edp/

Modul MIESZANY - nie da sie zrobic calosci w jednym Block Design, bo
kluczowy skladnik (dzielony quad GTX) wymaga IP niedzialajacego w BD:

```
                    NON-PROJECT (recznie w Tcl, poza BD)
  quad 0 (bank 115):
    gtwizard #A (usesharedlogic=0, kanaly 0-1) -> tor eDP #1 (dp_tx_subsystem w BD)
    gtwizard #B (usesharedlogic=1, kanaly 2-3) -> tor eDP #2 (dp_tx_subsystem w BD)
  quad 1 (bank 116):
    vid_phy_controller (caly quad, 4 kanaly, ale uzywane tylko 2) -> tor eDP #3
    (tu wrapper IP jest OK, bo tor #3 dostaje caly quad dla siebie -
    nie trzeba dzielic, wiec nie trzeba omijac ograniczenia)

                    BLOCK DESIGN (edp_bd.tcl, w BD)
  microblaze_0 (sterowanie AXI-Lite)
  axi_interconnect (MB -> 3x dp_tx_subsystem)
  dp_tx_subsystem_0/1/2 (SST, LANE_COUNT=2, PHY_type_External=1)
    <- strumien wideo AXI4-Stream (od dekodera MJPEG, poza tym modulem)
    <- polaczenie PHY z gtwizard (tor 1,2) lub vid_phy_controller (tor 3)
       PRZEZ GRANICE BD - sygnaly PHY wchodza/wychodza jako porty top-level
```

**Uzasadnienie mieszanej architektury (nie upraszczac do samego BD ani
samego RTL):** BD jest wlasciwym narzedziem dla podsystemu procesorowego
(MicroBlaze + AXI Interconnect + AXI-Lite peryferia) - robienie tego
recznie w RTL byloby duzo wiecej pracy bez korzysci. Ale `gtwizard` z
Shared Logic MUSI byc poza BD, bo BD go nie wspiera. Granica miedzy nimi:
sygnaly PHY (TXDATA/TXOUTCLK/reset-done) jako zwykle porty modulu BD
(`PHY_type_External=1` w dp_tx_subsystem jest DOKLADNIE po to).

## Do zweryfikowania empirycznie (nastepny krok)

Rzeczywiste polaczenie `gtwizard` (non-project) -> `dp_tx_subsystem`
(w BD, `PHY_type_External=1`) - agent zaznaczyl brak potwierdzonego
precedensu specyficznie dla DisplayPort (staff Xilinxa na forum: "nie
spotkalismy sie z takim wdrozeniem"). To jest teraz GLOWNE ryzyko
techniczne modulu `edp/`, wiekszy niz samo sterowanie AXI-Lite.

---

# Shared Logic gtwizard - mechanizm potwierdzony (2026-09-02)

Zmierzone przez porownanie wygenerowanych plikow RTL dwoch instancji
`gtwizard` z roznym `gt0_usesharedlogic`.

## Mechanizm (odwrotny do intuicyjnego, ale jednoznaczny)

| | `usesharedlogic=0` | `usesharedlogic=1` |
|---|---|---|
| Plik `_common.v` | **brak** | **jest** (zawiera `GTXE2_COMMON`... ale patrz nizej) |
| Wejscie zegara ref. | `gt0_gtrefclk0/1_in` - **juz zbuforowany** | `q0_clk1_gtrefclk_pad_p/n_in` - **surowe piny roznicowe**, generuje IBUFDS_GTE2 wewnatrz |
| `gt0_txusrclk_out` | brak (uzywa wlasnego `gt0_txusrclk_in`) | **generuje i wystawia** na zewnatrz |
| Rola | "klient" - podlacza sie do gotowych sygnalow | "wlasciciel" - generuje wspolna infrastrukture (bufor refclk, reset FSM) dla calego quadu |

**Wniosek: `usesharedlogic=1` = "Shared Logic in Core" (generuje), `=0` =
"Shared Logic in Example Design" (importuje)** - nazwa parametru jest
myloca (sugerowalaby odwrotnie), ale mechanizm jest jednoznaczny po
porownaniu wygenerowanych portow.

## Oba warianty maja NIEZALEZNY kanal (CPLL)

Potwierdzone w RTL: `TXSYSCLKSEL=2'b00` (na sztywno) = **CPLL**, nie QPLL
(UG476). Kazda instancja ma wlasny `gt0_cpllreset_in`, wlasne
`gt0_txdata_in[19:0]`, wlasne piny `gtxtxp/n_out`. To zgadza sie z
researchem: CPLL jest per-kanal, niezalezny od reszty quadu.

## Nastepny krok (w toku)

Test integracji: obie instancje faktycznie umieszczone w TYM SAMYM quadzie
fizycznym (X0Y0-X0Y3), z instancja "wlasciciel" (usesharedlogic=1)
dostarczajaca refclk instancji "klient" (usesharedlogic=0) - sprawdzenie
przez PnR, czy narzedzie to zaakceptuje i poprawnie rozmiesci.
