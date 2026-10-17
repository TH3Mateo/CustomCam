# USB_GPIF — odbiornik strumienia GPIF II z CYUSB3014

## Context

Projekt `expander/` to adapter **USB3.0 → LVDS**: strumień obrazu w MJPEG wchodzi
po USB3.0 przez PHY Cypress CYUSB3014 (EZ-USB FX3), jest dekodowany w FPGA
GW2AR-18 i wystawiany na **dwa wyświetlacze FullHD 60FPS** po liniach LVDS.

Sprzęt jeszcze nie istnieje. Ten krok ma dać **wstępny kod do oszacowania budżetu
GPIO i zasobów chipu** — pinout nie jest utrwalony, więc numery pinów w `.cst` są
wstępne i mają być łatwe do przestawienia.

Zakres tego kroku (ustalony z użytkownikiem): **tylko moduł `USB_GPIF` + testbench.**
Dekoder MJPEG i nadajnik LVDS powstaną osobno. Struktura ma naśladować
`../IRIS` (monorepo samodzielnych podprojektów Gowin).

### Decyzje przyjęte

| Kwestia | Decyzja |
|---|---|
| Tryb GPIF II | **Synchronous Slave FIFO, FPGA = master** (FPGA steruje SLRD#/SLOE# i czyta DQ[31:0]) |
| Źródło PCLK | **FPGA generuje PCLK 100 MHz** z własnego PLL i podaje do FX3 — **eliminuje CDC** (patrz §5) |
| Zegar zewnętrzny | 100 MHz na całość; moduły mogą mieć szybszy zegar z PLL |
| LVDS (w budżecie pinów) | 2× single-link 4-lane 24 bpp = 2×5 par = 20 pinów |
| Obudowa | **QN88** (`GW2AR-LV18QN88C8/I7`), jak w IRIS — 66 user I/O |
| Flash | **MSPI** (FPGA master, jak w IRIS) — 4 piny zarezerwowane |
| SSPI | oddane na GPIO przez `set_option -use_sspi_as_gpio 1` |
| UART debug | **pominięty** w tym kroku |
| Konfiguracja FX3 | **mikrokontroler na PCB** — nie obciąża FPGA ani budżetu pinów |

### Przepustowość (odpowiedź na pytanie o Mbit/s)

```
Magistrala 32 bit x 100 MHz (sufit GPIF II)     3200 Mbit/s = 400 MB/s
Po przerwach na przelaczanie buforow DMA (4 kB) 3191 Mbit/s = 399 MB/s
--- limit nadrzedny ---
USB 3.0 SS: 5 Gbit/s linii - 8b/10b - protokol
Praktyka FX3 (dok. Cypress): 375 MB/s          3000 Mbit/s <- WASKIE GARDLO
```
**Realnie ~3000 Mbit/s.** Wąskim gardłem jest USB, nie GPIF — moduł ma ~6% zapasu
ponad to, co fizycznie dostarczy FX3, więc jest poprawnie zwymiarowany.
Wymagany stopień kompresji MJPEG: 7,13 Gbit/s / 3,0 Gbit/s = **≥2,4×**
(typowy MJPEG 10–20×, więc bardzo duży margines).

---

## Ustalenia z dokumentacji (zmierzone, nie zgadywane)

### 1. Czy MSPI jest wliczone w 66 GPIO? **TAK.**

`GW2AR_application_note.pdf` (UG229), Tabela 2-3, przypis [1]:
> *"Single end/Differential/LVDS I/O quantity **include CLK pins, and download pins**."*

Potwierdza to tabela pinów (`GW2AR_pin_description.pdf`) — piny konfiguracyjne są
**dwufunkcyjne**, występują jako zwykłe I/O z aliasem:

| Funkcja | Nazwa w tabeli | Pin QN88 |
|---|---|---|
| JTAG | `IOR25A/TDO`, `IOR25B/TMS`, `IOR26A/TCK`, `IOR26B/TDI` | 8, 5, 6, 7 |
| MSPI | `IOR33A/MI/D7`, `IOR33B/MO/D6`, `IOR34A/MCS_N/D5`, `IOR34B/MCLK/D4` | 62, 61, 60, 59 |
| SSPI | `IOR36A/SO/D1`, `IOR36B/SSPI_CS_N/D0`, `IOR35A/FASTRD_N/D3` | 56, 55, 57 |

**Wniosek:** 66 to pula łączna — piny konfiguracyjne nie są „darmowe", trzeba je
odjąć od budżetu.

**Jak steruje się uwolnieniem tych pinów (zweryfikowane w IRIS):**
decyduje `set_option -use_sspi_as_gpio 1` w **`run_pnr.tcl`** (generowanym przez
`generate_pnr_script.py:106`), **nie** wpis `set SSPI regular_io` w `device.cfg`.
IRIS ma tę opcję włączoną i dzięki temu prowadzi `MOSI2` na pinie 55 i `CS_N2`
na 56 — czyli na pinach SSPI. (W `device.cfg` IRIS ma `set SSPI regular_io = false`;
`true` widoczne w tym pliku to komentarz-podpowiedź toolchainu, nie ustawienie.)

**Przyjęty podział dla expandera — jednoznacznie:**

| Grupa | Piny QN88 | Decyzja |
|---|---|---|
| **JTAG** | 5, 6, 7, 8 | **zarezerwowane** — bez nich nie ma jak programować układu |
| **MSPI** | 59, 60, 61, 62 | **zarezerwowane pod flash** (FPGA jako master, jak w IRIS) |
| **SSPI** | 55, 56, 57 | **oddane na GPIO** przez `-use_sspi_as_gpio 1` |

MSPI i SSPI to **rozłączne grupy pinów** — zachowanie flasha na MSPI nie koliduje
z użyciem SSPI jako GPIO. Koszt netto konfiguracji: 8 pinów (JTAG + MSPI).

### 2. Czy da się ograniczyć piny kontrolne GPIF? **TAK, z 44 do 35.**

Tor jest **wyłącznie odbiorczy** (FX3 → FPGA), więc znika cała połowa zapisowa:

| Sygnał | Pełny | Min | Uzasadnienie cięcia |
|---|---:|---:|---|
| `DQ[31:0]` | 32 | 32 | nieredukowalne |
| `PCLK` | 1 | 1 | nieredukowalne |
| `SLRD#` | 1 | 1 | konieczne |
| `SLOE#` | 1 | 0 | **zwarte z SLRD# na PCB** — przy czystym odczycie oba mają identyczny przebieg |
| `SLCS#` | 1 | 0 | **na stałe do GND na PCB** — jedno urządzenie na magistrali |
| `SLWR#`, `PKTEND#` | 2 | 0 | **tylko dla zapisu FPGA→FX3**, nie występuje |
| `A[1:0]` | 2 | 0 | **na stałe 0** — jeden socket, przełączanie wątków w automacie GPIF II |
| `FLAGA..D` | 4 | 1 | **1 flaga dedykowana** (empty dla bieżącego wątku) wystarczy do flow control |
| **RAZEM** | **44** | **35** | **oszczędność 9 pinów** |

Ryzyko cięcia: zwarcie SLOE#+SLRD# jest bezpieczne przy odczycie, ale **usuwa
możliwość trzymania danych na magistrali bez inkrementacji wskaźnika FIFO** —
sterownik musi to respektować (nie ma "peek"). To akceptowalne dla strumienia
ciągłego. Jedna flaga zamiast dwóch **wyklucza bezprzerwowe przełączanie socketów**
(brak podglądu drugiego wątku) — kosztuje kilka cykli martwych na granicy bufora
DMA, nieistotne przy zapasie przepustowości poniżej.

### 3. Budżet pinów — mieści się, ale ciasno

```
Pula user I/O QN88                    66
  - JTAG        (5,6,7,8)              4   zarezerwowane
  - MSPI        (59,60,61,62)          4   zarezerwowane na flash
                                     ----
Dostepne (w tym 3 piny SSPI)          58

GPIF II DQ[31:0]                      32
GPIF II PCLK   (WYJSCIE -> FX3)        1
GPIF II SLRD#                          1
GPIF II FLAG_EMPTY                     1
LVDS 2x (4 pary danych + 1 zegar)     20
clk100M        (WEJSCIE <- generator)  1
reset                                  1
                                     ----
RAZEM                                 57

ZAPAS                                  1 pin
```

**PCLK i `clk100M` to DWA ROZNE PINY** — `clk100M` jest wejściem z fizycznego
generatora 100 MHz na PCB (źródło systemowe), a `PCLK` wyjściem z PLL FPGA do FX3.
Wcześniejsza wersja tego dokumentu błędnie traktowała je jako jedną pozycję.

**Zapas 1 pin przyjęty świadomie.** Jeśli okaże się potrzebny większy, wracamy do
tabeli w `PINOUT.md` (najtańsze: rezygnacja z flash MSPI = +4 piny).

QN88 ma **22 pary True LVDS** — potrzeba 10. Mieści się z zapasem.

### 4. Przepustowość — z dużym zapasem

```
GPIF32 @ 100 MHz          = 3200 Mbit/s = 400 MB/s  (sufit sprzetowy)
po narzucie buforow DMA   = 3191 Mbit/s             (bufor 4 kB)
FX3 przez USB 3.0 realnie = 3000 Mbit/s = 375 MB/s  <- WASKIE GARDLO

2x 1080p60 24bpp surowo   = 7130 Mbit/s             (po dekompresji)
=> wymagany stopien kompresji MJPEG >= 2.4x         (typowy MJPEG: 10-20x)

LVDS 7:1 @ 148.5 MHz      = 1039 Mbit/s na pare
   limit gearboxa OSER10  = 1200 Mbit/s             -> zapas ~13%
```

### 5. Źródło PCLK i timing — **sedno trudności modułu**

`CYUSB3014.pdf` Tabela 13/15: FX3 ma **`tCO` = 7 ns max** (zegar → ważne dane)
przy okresie PCLK **10 ns**. To obowiązuje w obu wariantach — `tCO` jest zawsze
liczone względem PCLK widzianego przez FX3.

| | **A: PCLK od FX3** | **B: PCLK z FPGA** (wybrany) |
|---|---|---|
| Charakter | source-synchronous (zegar+dane w tę samą stronę) | round-trip (zegar tam, dane z powrotem) |
| Budżet @ posedge | 10 − 7 − tSU ≈ **2 ns** na trace+skew | 10 − tPD_clk − 7 − tPD_dat − tSU ≈ **0 ns** |
| Budżet @ negedge | ~7 ns | **~5 ns** |
| CDC | **wymagane** — własny oscylator FX3, async FIFO + kod Graya | **brak** — PCLK z tego samego PLL co `clk_core` |

**Wybrany wariant B.** Timing jest gorszy (round-trip zamiast jednokierunkowej
ścieżki), ale 5 ns marginesu na zboczu opadającym wystarcza, a **znika całe CDC** —
czyli najbardziej ryzykowny i najtrudniejszy do zweryfikowania fragment modułu.
Zysk dodatkowy: −1 BSRAM, mniej LUT, prostszy testbench.

**Konsekwencje, o których trzeba pamiętać:**
- Próbkowanie **zboczem opadającym** jest obowiązkowe w obu wariantach — musi
  trafić do komentarza nagłówkowego, bo jest nieoczywiste i łatwe do „naprawienia"
  przez pomyłkę.
- **100 MHz to sufit** — nie ma zapasu na podniesienie częstotliwości (i tak jest
  to limit GPIF II, więc nie boli).
- FX3 musi być skonfigurowany firmware'owo na **PCLK jako wejście** — do
  uzgodnienia przy projektowaniu PCB i firmware'u FX3.
- Wariant zapasowy, jeśli pomiary na sprzęcie nie potwierdzą marginesu:
  `IODELAY` na `DQ[31:0]` (GW2AR ma IODELAY na wejściach). Gdyby okazało się to
  niewystarczające — powrót do wariantu A (z pełnym CDC) jest możliwy bez zmian
  w pinout, kosztem złożoności RTL.

### 6. Mikrokontroler na PCB — podział odpowiedzialności

Na płytce jest **osobny mikrokontroler**, który zajmuje się wstępną konfiguracją
CYUSB3014. Konsekwencje dla FPGA:

- **FPGA nie musi bootować FX3** ani ładować jego firmware'u (FX3 potrafi bootować
  z I2C EEPROM / USB / SPI — to działka MCU, nie nasza).
- **Nie rezerwujemy pinów** na I2C/SPI do FX3 — dlatego zapas 1 pin jest realny,
  a nie optymistyczny.
- FPGA **zastaje FX3 już skonfigurowany** i gotowy na transfery GPIF II.

**Wynikające z tego założenie do zweryfikowania przy integracji:** moduł
`usb_gpif` startuje bez wiedzy, czy FX3 jest gotowy. Automat musi to tolerować —
przy braku danych `FLAG_EMPTY` po prostu trzyma odczyt wstrzymany, bez zawieszania
się i bez błędu. Nie zakładamy żadnej sekwencji startowej ani handshake'u z MCU.
Jeśli okaże się potrzebna sygnalizacja „FX3 gotowy" z MCU do FPGA — to **kolejny
pin**, którego przy zapasie 1 nie ma z czego wziąć (patrz tabela w `PINOUT.md`).

---

## Architektura modułu

```
                  domena PCLK (100 MHz, od FX3)      | domena rdzenia (clk_core, PLL)
                                                     |
  FX3 ──DQ[31:0]──> [rejestr wejściowy, negedge] ──> |
      ──FLAG_EMPTY─> [sync 2-FF] ─┐                  |
      <─SLRD#/SLOE#─ [gpif_fsm] <─┘                  |
                          │                          |
                          └──> [async FIFO, BSRAM] ──┼──> data_o[31:0]/valid_o/ready_i
                                                     |
```

Trzy zegary:
- `clk100M` — pin wejściowy, źródło systemowe
- `PCLK` — od FX3, **niezależna domena** (własny oscylator FX3) → wymagane CDC
- `clk_core` — z rPLL, dla reszty systemu (dekoder MJPEG); w tym kroku np. 100 MHz,
  docelowo wyżej

### Pliki

Katalog `usb_gpif/`, na wzór `../IRIS/dac_drive/` (najświeższy wzorzec, dwa warianty
buildu dzielące jedno `src/`):

| Plik | Rola |
|---|---|
| `src/hdl/usb_gpif_pkg.sv` | `localparam` szerokości magistrali, głębokość FIFO, `typedef enum` stanów |
| `src/hdl/usb_gpif_rx.sv` | automat GPIF II slave-FIFO read + próbkowanie negedge + sync flagi |
| `src/hdl/usb_gpif_fifo.sv` | asynchroniczne FIFO CDC (BSRAM `SDPB`), wskaźniki Graya |
| `src/hdl/usb_gpif.sv` | rdzeń — składa `_rx` + `_fifo`, wystawia `valid/ready` |
| `src/hdl/usb_gpif_dev.sv` | wariant bring-up: instancjonuje rdzeń, licznik odebranych słów + checker wzorca testowego na LED/debug |
| `src/hdl/gowin_rpll/gowin_rpll.v` | PLL (skopiowany i przestrojony z IRIS) |
| `src/constraints/usb_gpif.cst`, `.sdc` | wariant rdzenia |
| `src/constraints/usb_gpif_dev.cst`, `.sdc` | wariant bring-up |
| `src/tb/usb_gpif_tb.sv` | testbench z **modelem behawioralnym FX3** |
| `usb_gpif.gprj`, `usb_gpif_dev.gprj` | listy plików (źródło prawdy dla Makefile) |
| `Makefile`, `device.cfg`, `generate_*.py` | skopiowane verbatim z `../IRIS/dac_drive/` |
| `CYUSB3014.pdf` | przeniesiony do katalogu modułu (konwencja IRIS) |

Dodatkowo w korzeniu projektu: **`CLAUDE.md`** i **`PINOUT.md`** — patrz niżej.

### Kluczowe punkty implementacji

**`usb_gpif_rx.sv`** — automat 4-stanowy (`S_IDLE`, `S_ARM`, `S_READ`, `S_DRAIN`):
- `SLRD#`/`SLOE#` aktywne w stanie zliczania; `SLOE#` jako osobny port RTL nawet
  jeśli na PCB zwarty z `SLRD#` — dzięki temu decyzja o zwarciu jest odwracalna
  bez zmian w RTL, wystarczy `.cst`.
- **Latencja `tCO` w potoku:** dane odpowiadające `SLRD#` w cyklu N pojawiają się
  dopiero w cyklu N+1/N+2. Automat musi utrzymać `valid` opóźnione o tę samą
  liczbę cykli (parametr `RD_LATENCY`, domyślnie 2) — to najczęstszy błąd w tym
  interfejsie i musi być jawnym parametrem, nie liczbą wpisaną w kod.
- Flaga empty: **przerwanie odczytu z wyprzedzeniem**. FLAG ma `tCFLG` = 8 ns
  propagacji + 2 cykle synchronizatora, więc od zauważenia „empty" do zatrzymania
  mija kilka cykli — potrzebny margines (odczyt zatrzymywany, gdy FIFO odbiorcze
  ma mniej niż `ALMOST_FULL_MARGIN` miejsc).

**`usb_gpif_fifo.sv`** — asynchroniczne FIFO na BSRAM. IRIS **nie ma precedensu**
dla BSRAM ani FIFO (potwierdzone: `SDPB`/`DPB` występują tylko w `prim_sim.v`
biblioteki vendora), więc to nowy element. Głębokość 512×32 = 16 kb = 1 BSRAM
(z 46 dostępnych). Wskaźniki w kodzie Graya, po 2-FF w każdą stronę.

**`.sdc`** — pierwszy w tym repo z dwoma zegarami:
```tcl
create_clock -name clk100M -period 10.000 [get_ports {clk100M}]
create_clock -name PCLK    -period 10.000 [get_ports {PCLK}]
```
**Uwaga z IRIS `top_module.sdc` (udokumentowana porażka, nie powtarzać):**
`set_clock_groups -asynchronous` jest odrzucane (zegary z PLL nie istnieją na
etapie parsowania constraintów), a `set_false_path` w Gowin V1.9.9 **fizycznie
usuwa ścieżkę sygnału** (zweryfikowane porównaniem bitstreamów). Dlatego
rozdzielenie domen musi być zrobione **strukturalnie** (FIFO + synchronizatory),
a nie constraintami. Nie próbować „poprawiać" tego przez SDC.

**Testbench `usb_gpif_tb.sv`** — model FX3 musi odtwarzać **realne** zachowanie,
inaczej test niczego nie dowodzi:
- `PCLK` generowany niezależnie, z **celowym przesunięciem fazy** względem
  `clk100M` (sprawdzenie CDC),
- dane wystawiane po **`tCO` = 7 ns** od zbocza narastającego (`#7`),
- `FLAG_EMPTY` opadająca po `tCFLG` = 8 ns,
- opróżnianie się bufora i przerwy między buforami DMA (test flow control),
- odbiornik z **losowym `ready_i`** (backpressure) — sprawdza, czy FIFO nie gubi
  słów, gdy dekoder MJPEG zwalnia.
- Wzorzec: licznik inkrementujący, checker liczy błędy → banner `PASS`/`FAIL`
  po polsku, jak w IRIS.

### Konwencje (z `../IRIS/CLAUDE.md` — zachować)

- SystemVerilog `.sv`, synteza `sysv-2017`, symulacja `iverilog -g2012`
- Porty ANSI: `input wire`/`output wire` + **UPPER_CASE dla nazw pinów fizycznych**
  (`DQ`, `PCLK`, `SLRD_N`), `input logic`/`output logic` + `_i`/`_o` w modułach wewnętrznych
- Reset **synchroniczny, aktywny wysoko**, `if (reset)` wewnątrz `always_ff @(posedge clk)`
- Sufiksy: `_r` rejestry, `_int` kopie wewnętrzne, `_n`/`_N` aktywne nisko,
  `_s1`/`_s2` stopnie synchronizatora
- Prefiks instancji **`u_`**, porty wyrównane, nieużywane wyjścia jako jawne `()`
- **Komentarze po polsku, ASCII bez znaków diakrytycznych** ("polaczenie", nie "połączenie")
- Wcięcie 4 spacje (2 w `package`)
- Baner nagłówkowy `// ===...` z opisem i **uzasadnieniem decyzji**
- Top module **nie jest nigdzie deklarowany** — `GowinSynthesis` wybiera moduł,
  którego nikt nie instancjonuje, więc o topie decyduje lista plików w `.gprj`.
  Każdy `.gprj` musi mieć dokładnie jeden nieinstancjonowany moduł.

---

## Pliki kontekstu projektu — `expander/.claude/`

Wszystkie ustalenia trzymamy **lokalnie w repo**, w `expander/.claude/`, zeby
jechaly razem z projektem i byly do znalezienia przez kogos, kto oglada sam
projekt. Nic nie ladujemy do `~/.claude/`.

| Plik | Stan | Zawartosc |
|---|---|---|
| `.claude/PINOUT.md` | **utworzony** | zywy budzet GPIO, redukcja GPIF 44->35, piny konfiguracyjne, skad wziac zapas |
| `.claude/PLAN_usb_gpif.md` | **utworzony** | ten plan |
| `.claude/DECYZJE.md` | do zrobienia | `tCO`=7 ns i probkowanie negedge, PCLK z FPGA, ograniczenia SDC w Gowin V1.9.9, podzial z MCU |
| `CLAUDE.md` (korzen) | do zrobienia | cel projektu, tor danych, toolchain, konwencje — wzorowany na `../IRIS/CLAUDE.md` |

`CLAUDE.md` zostaje w korzeniu (tam go szuka Claude Code i czlowiek), reszta

**Wyniki pomiarow:** `.claude/WYNIKI_usb_gpif.md` (zasoby, timing, korekta budzetu pinow).
ustalen w `.claude/`, zeby nie zasmiecac korzenia projektu.

## Weryfikacja

1. **Symulacja funkcjonalna** — `cd usb_gpif && make simulate`
   Oczekiwane: `=== PASS: wszystkie testy zaliczone ===`, zero zgubionych słów
   przy backpressure i na granicach buforów DMA.

2. **Synteza + PnR obu wariantów** — `make` oraz `make PRJ=usb_gpif_dev`
   To jest **właściwy cel tego kroku** — z raportów odczytać i zapisać w `PINOUT.md`:
   - `impl/pnr/usb_gpif.rpt.txt` → zużycie LUT/FF/BSRAM (baza: 20736 LUT4, 46 BSRAM)
   - liczbę faktycznie użytych I/O
   - **0 naruszeń setup/hold** i osiągnięte Fmax dla obu domen

3. **Ekstrapolacja budżetu** — na podstawie zmierzonego zużycia ocenić, ile
   zasobów zostaje na dekoder MJPEG (największy konsument: bufory IDCT i tablice
   Huffmana) i nadajnik LVDS. **To jest odpowiedź na pytanie „czy całość zmieści
   się w GW2AR"** — bez tego kroku wynik jest tylko zgadywaniem.

4. **Bez sprzętu** — flash/upload niedostępne (hardware nie istnieje).
   `make flash` zostaje w Makefile na przyszłość, ale nie jest teraz uruchamiany.

## Ryzyka

- **Timing GPIF na granicy.** `tCO`=7 ns przy okresie 10 ns to najwęższe miejsce
  całego projektu. Negedge daje margines na papierze; ostateczne potwierdzenie
  wymaga sprzętu. Jeśli PnR pokaże problem — `IODELAY` na `DQ`.
- **FIFO/BSRAM bez precedensu w repo.** Pierwsze użycie BSRAM w tym toolchainie;
  możliwe niespodzianki w inferencji vs. jawna prymitywa `SDPB`.
- **Zapas 5 pinów jest ciasny.** Każdy dodatkowy sygnał (I2C do EDID wyświetlacza,
  UART debug, reset FX3) zjada go natychmiast. Jeśli okaże się za mało —
  pierwsze do odzyskania są piny SSPI (2–3), potem trzeba zejść z LVDS na
  18 bpp (3 pary zamiast 4 → oszczędność 4 pinów).
