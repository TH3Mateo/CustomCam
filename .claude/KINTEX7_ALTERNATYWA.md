# XC7K325T jako alternatywa dla GW2AR-18 (rozeznanie 2026-08-29)

Zrodlo: `XC7K325T-2FFG900C.pdf` = **DS182 v2.19** (Kintex-7 DC and AC Switching
Characteristics). To datasheet **elektryczny** - nie ma w nim liczby LUT/BRAM/DSP
ani tabeli pinow. Te liczby sa w DS180 (7 Series Overview) i UG475 (Packaging),
ktorych w repo NIE MA. Ponizej: co wynika wprost z DS182 + co trzeba dociagnac.

Rozwazany konkret: **XC7K325T-2FFG900C** (speed grade -2, obudowa FFG900,
zakres komercyjny 0..85 C).

> **KOREKTA 2026-08-29 - trzy zalozenia z pierwszej wersji byly bledne:**
> 1. **Uklad jest juz kupiony** - 100 zl, z wylutu. Argument o cenie ukladu
>    (setki USD) **nie obowiazuje**. Uklady z wylutu sa tanie wlasnie dlatego,
>    ze Vivado dla K325T wymaga platnej licencji - odpada wiec hobbysta.
> 2. **Istnieje otwarty toolchain: openXC7** (yosys + nextpnr-xilinx + prjxray),
>    ktory jawnie wspiera Kintex7 70T/160T/**325T**/420T/480T. Argument
>    "trzeba kupic Vivado" **nie obowiazuje**. Szczegoly nizej.
> 3. Wiekszy uklad otwiera **3 monitory / wyzszy framerate / wyzsza
>    rozdzielczosc / USB 10 Gbps** - to jest wlasciwa motywacja, a nie samo eDP.

## Co daje - twarde liczby z DS182

### 1. LVDS: 1250 Mb/s zamiast 1040 Mb/s (Tabela 17)

| | Mb/s na pare |
|---|---:|
| GW2AR OSER10, sufit | 1200 (nasz punkt pracy 1040) |
| K7 -2, **HR bank**, DDR LVDS TX (OSERDES) | **1250** |
| K7 -2, **HP bank**, DDR LVDS TX (OSERDES) | **1400** |

Zysk realny, ale **niewielki i nie rozwiazuje problemu eDP**. Podniesienie
sufitu z 1200 na 1400 Mb/s nadal nie siega eDP RBR (1620 Mb/s) na zwyklym I/O.

Uwaga na napiecia: `LVDS_25` (VCCO 2.5V) istnieje **tylko w bankach HR**.
Banki HP maja VCCO max 1.89V i standard nazywa sie tam po prostu `LVDS` (1.8V).
Czyli szybsze 1400 Mb/s wymaga LVDS 1.8V, a nie 2.5V - inny poziom common-mode
niz w GW2AR. Sam VOD/VOCM sie zgadza (247-600 mV / 1.0-1.425 V), wiec panel
LVDS przyjmie jedno i drugie, ale VCCIO na PCB jest inne.

### 2. GTX - to jest wlasciwy zysk: eDP bezposrednio z FPGA

DS182 Tabela 56, dla **-2**:

| | Gb/s |
|---|---:|
| FGTXMIN | 0.500 |
| **FGTXMAX, FFG900, -2** | **6.6** |
| (FGTXMAX 10.3125 dotyczy FBG676/FBG900, nie FF900) |  |

Rozstrzyga to blokade opisana w `.claude/LVDS_EDP.md`:
- eDP **RBR 1.62 Gb/s** - miesci sie (CPLL, dzielnik 2: zakres 1.6-3.3 Gb/s)
- eDP **HBR 2.7 Gb/s** - miesci sie (CPLL dzielnik 2, albo QPLL 2.965-4.0 przez /2)
- eDP **HBR2 5.4 Gb/s** - miesci sie (CPLL dzielnik 1: 3.2-6.6 Gb/s)

**Wniosek sprzetowy: na K7 mostek LT8911EX przestaje byc potrzebny.** 1080p60
24bpp = 3.56 Gbps payload -> RBR x4 albo HBR x2, obie opcje w zasiegu GTX.
Zostaje caly stack protokolu do napisania w HDL: 8b/10b, scrambler, MSA,
link training po AUX (kanal dwukierunkowy, wymaga zewnetrznego bufora),
HPD. To wciaz **duzo wiecej pracy niz kupienie LT8911EX** - ale sprzetowo
staje sie mozliwe.

**ALE: GTX a openXC7 - stan na 2026-08.** nextpnr-xilinx dla xc7 wspiera
`GTPE2_COMMON` / `GTPE2_CHANNEL` (Artix-7), czyli **nie GTXE2** wprost.
Wsparcie GTX na Kintexie doszlo dopiero w **PR #88 (kwiecien 2026)**:
"GTX channel driven by IBUFDS (CPLL mode) support, with PCIe working on
Kintex 7". Zastrzezenia z samego PR:
- dziala **tylko CPLL** przez `IBUFDS_GTE2`, z pominieciem `GTXE2_COMMON`
- **QPLL nie dziala** dla niskich bitrate ("seems unable to give a low bit
  rate like 5 Gbps that works with PCIe")
- wymagalo towarzyszacych latek w `prjxray` i `prjxray-db`
- otwarte problemy: #100 (IBUFDS_GTE2.O do GT i BUFG jednoczesnie = martwy
  zegar fabric), #101 (GTPE2_CHANNEL: 80 domyslnych atrybutow FASM rozni sie
  od biblioteki Xilinx)

Czyli GTX na openXC7 to **swiezy, czesciowo dzialajacy feature**, nie
dojrzala sciezka. Dla eDP RBR (1.62 Gb/s) trzeba by CPLL z dzielnikiem 2
(zakres 1.6-3.3 Gb/s) - w teorii w zasiegu, w praktyce nikt tego nie zrobil.

### 3. Piny - problem "zapas 1 pin" znika calkowicie

QN88 to 66 user I/O, z czego realnie 57-61 i to kosztem flash (JTAG-only
programowanie). FFG900 to obudowa 900-kulkowa, ~500 user I/O w tej klasie
(dokladna liczba: **UG475, nie ma jej w DS182**). Budzet 57 pinow przestaje
byc jakimkolwiek ograniczeniem - starczy na 4 wyswietlacze i pelen GPIF II
dwukierunkowy (44 piny zamiast okrojonych 35).

### 4. Zasoby logiczne

DS182 nie podaje. Z pamieci/DS180: XC7K325T to ~326k logic cells, 445 BRAM36
(~16 Mb), 840 DSP48E1 - **do zweryfikowania w DS180**, nie zgaduj na tej
podstawie decyzji zakupowej.

Skala vs GW2AR-18 (20.7k LUT, 46 BSRAM ~0.9 Mb, 48 DSP): rzedy wielkosci.
Dekoder MJPEG dla 2x FullHD 60 FPS przestaje byc ryzykiem projektowym.
16 Mb BRAM to juz **pelny framebuffer 1080p** przy redukcji bpp (1080p RGB565
= 33 Mb, wiec nie caly klatka w RGB888, ale bufory linii/pasm - z ogromnym
zapasem). Na GW2AR framebuffer nie wchodzil w gre w ogole.

### 5. MMCM zamiast PLL (Tabela 41, -2)

| | |
|---|---|
| Wejscie | 10 - 933 MHz |
| VCO | 600 - 1440 MHz |
| Static phase offset | 0.12 ns |
| Dynamic phase shift | do 500 MHz |

Do tego **IDELAYE2/ODELAYE2** (linie opoznajace z kalibracja) - to jest
bezposrednie rozwiazanie problemu z `.claude/WYNIKI_usb_gpif.md`:
> "wymusic siec zegarowa (BUFG/CLKDIV) albo przejsc na IODELAY zamiast negedge"

Na K7 IDELAY istnieje natywnie, wiec hack z probkowaniem DQ na zboczu opadajacym
(przy tCO=7ns FX3) mozna zastapic kalibrowanym opoznieniem wejsciowym. Znika
tez WARN PR1014 o generycznym routingu zegara.

## Co to kosztuje

### Zasilanie - z porzadnego jednoszynowego na wieloszynowe sekwencjonowane

DS182 Tabela 2 + 6, XC7K325T-2:

| Szyna | Napiecie | Prad spoczynkowy (typ, -2) |
|---|---|---:|
| VCCINT | 1.00 V ±3% | **810 mA** |
| VCCBRAM | 1.00 V (ta sama szyna co VCCINT) | 19 mA |
| VCCAUX | 1.80 V ±5% | 68 mA |
| VCCO (HR) | 1.14 - 3.465 V | 1 mA/bank |
| VCCO (HP) | 1.14 - **1.89 V** | 2 mA |
| VMGTAVCC | 1.00 V | GTX |
| VMGTAVTT | 1.20 V | GTX |
| VMGTVCCAUX | 1.80 V | GTX |

**810 mA samego pradu spoczynkowego na VCCINT** - to jest zanim projekt cokolwiek
zrobi. GW2AR-18 jest w klasie dziesiatek mA. Do tego DS182 wymaga:
- sekwencji wlaczania: VCCINT -> VCCBRAM -> VCCAUX -> VCCAUX_IO -> VCCO
- osobnej sekwencji GTX: VCCINT -> VMGTAVCC -> ...
- prad rozruchowy **do 460 mA na transceiver** przy narastaniu VMGTAVCC
- ICCINTMIN = ICCINTQ + 600 mA, czyli **~1.4 A minimum na VCCINT**
- filtrow LC na kazdej szynie GTX (UG476)

To przebudowa calej sekcji zasilania PCB: kilka przetwornic step-down
z kontrolerem sekwencji, zamiast prostego LDO.

### Obudowa

FFG900 = 900 kulek BGA, raster 1.0 mm, ~31x31 mm. Wymaga PCB **min. 8-10 warstw**
z via-in-pad / HDI dla wyprowadzenia GTX. QN88 to QFN, ktory dalo sie zrobic na
4 warstwach. To jest inna klasa kosztu i innego producenta PCB.

### Toolchain: openXC7, nie Vivado

**K325T NIE jest objety darmowa licencja Vivado** - to wlasnie dlatego uklady
z wylutu sa tanie. Sciezka to **openXC7** (`github.com/openXC7/toolchain-installer`),
czyli yosys + nextpnr-xilinx + prjxray, instalowany przez Nix.

Deklarowane wsparcie: "Xilinx 7 series FPGAs (Spartan7, Artix7, Zynq7), with
added support for Kintex7 FPGAs (70T, 160T, **325T**, 420T, 480T)".
Istnieje referencyjne repo `openXC7/xc7k325t-blinky-nextpnr`.

Wspierane prymitywy xc7 (wg README nextpnr-xilinx) - **wszystko czego projekt
potrzebuje po stronie LVDS i GPIF jest na liscie**:
- LUT (takze fractured), FF, DRAM (tylko RAM64X1D), carry (CARRY4), SRL16E/SRLC32E
- **BRAM**, IO
- **OSERDESE2, ISERDESE2**, IDDR, ODDR, **IDELAYE2, ODELAYE2**, IDELAYCTRL
- BUFGCTRL, BUFG, BUFH, BUFHCE
- **PLLE2_BASIC/ADV, MMCME2_ADV, MMCME2_BASIC**
- **DSP48E1** (kaskadowanie dziala)
- IBUFDS_GTE2, GTPE2_COMMON, GTPE2_CHANNEL (+ GTXE2 od PR #88, patrz wyzej)

Znane ograniczenie: brak deduplikacji wezlow -> **bardzo duze bazy danych**
ukladu (dla 325T spodziewac sie dlugiego pierwszego builda i duzego RAM).

Plusy vs Gowin V1.9.9: znikaja ograniczenia z CLAUDE.md - w nextpnr nie ma
buga "set_false_path fizycznie usuwa sciezke". Minusy: nextpnr ma **inny,
slabszy model timingu** niz Vivado i mniej dojrzalego wsparcia dla trudnych
przypadkow; nie ma tez wsparcia dla twardych blokow typu PCIe.

Cala infrastruktura z `../IRIS` (`generate_pnr_script.py`, `device.cfg`,
Makefile pod Gowin CLI) idzie do kosza. Kod HDL zostaje - poza:
- `TLVDS_OBUF` -> `OBUFDS`
- `OSER10` -> `OSERDESE2`
- prymitywy BSRAM Gowin -> wnioskowanie z yosys albo `RAMB36E1` wprost
- `simlib/gw2a/prim_sim.v` -> biblioteki `unisim`

Modul `usb_gpif` (257 LUT) to przepisanie na jedno popoludnie.

Cala infrastruktura z `../IRIS` (`generate_pnr_script.py`, `device.cfg`,
Makefile pod Gowin CLI) idzie do kosza. Kod HDL zostaje - poza:
- `TLVDS_OBUF` -> `OBUFDS`
- `OSER10` -> `OSERDESE2`
- prymitywy BSRAM Gowin -> XPM / `BRAM_SDP_MACRO`
- `simlib/gw2a/prim_sim.v` -> biblioteki `unisim`

Modul `usb_gpif` (257 LUT) to przepisanie na jedno popoludnie.

### Cena - argument NIEAKTUALNY dla prototypu

Uklad **kupiony za 100 zl z wylutu**. Cena katalogowa (setki USD) nie ma
znaczenia dla sztuki prototypowej.

Co zostaje z kosztow:
- **PCB** - BGA900, 1.0 mm raster, min. 8-10 warstw. To nadal wielokrotnosc
  kosztu 4-warstwowego PCB pod QFN88.
- **montaz** - BGA900 z wylutu wymaga reballingu i profesjonalnego montazu;
  QFN88 da sie polozyc samemu.
- **ryzyko** - uklad z wylutu jest niewiadomej sprawnosci i historii termicznej.
  Warto miec zapasowa sztuke.
- **przy produkcji seryjnej** argument cenowy wraca w pelni - wylutow sie nie
  skaluje.

## Nowe mozliwosci, ktore otwiera wiekszy uklad

Motywacja nie jest juz "eDP bez mostka", tylko **rozszerzenie funkcjonalne**.
Trzy kierunki - kazdy badany osobno (wyniki dopisac tutaj):

### A. Trzy monitory zamiast dwoch

Ogranicza: liczba par LVDS w FFG900 (duzo, nie problem) oraz **pasmo USB**.
1080p60 24bpp bez kompresji = 3.56 Gbps na monitor. Trzy monitory = 10.7 Gbps
surowego wideo, wiec o wszystkim decyduje stopien kompresji na wejsciu.

### B. Wyzszy framerate / rozdzielczosc

Ten sam problem pasma. Dodatkowo sufit LVDS: 1250 Mb/s na pare (HR) /
1400 (HP) przy 4 parach danych - do sprawdzenia, ktore tryby jeszcze wchodza,
i czy panele LVDS powyzej 1080p60 w ogole istnieja (rynek idzie na eDP).

### C. USB 10 Gbps zamiast 5 Gbps

**FX3 tego nie zrobi** - CYUSB3014 to USB 3.1 Gen 1, 5 Gbps PHY, a GPIF II
32-bit @100 MHz daje praktycznie ~3.2 Gbps. Sufit jest w PHY, nie w FPGA.
Badane warianty zamiennika:
- **CYUSB3282FC** - do ustalenia czym dokladnie jest i czy ma interfejs do FPGA
- **EZ-USB FX10/FX20** - nastepca FX3 z USB 3.2 Gen2 (jesli istnieje)
- **mostek USB->NVMe (RTL9210 / JMS583) + FPGA udajace dysk** - patrz nizej
- **GTX Kintexa wprost** - odpada: to nie jest kontroler USB, a napisanie
  USB 3.x device controller w logice to praca poza skala tego projektu

### D. Kompresja miedzyramkowa zamiast MJPEG

Alternatywa dla podnoszenia pasma: **zostac przy 5 Gbps FX3, ale scisnac
mocniej**. MJPEG jest intra-only i bardzo nieefektywny; H.264/H.265 przy tej
samej jakosci daja wielokrotnie nizszy bitrate, co bezposrednio przeklada sie
na wiecej monitorow / wyzszy tryb w tym samym pasmie.

Koszt: dekoder miedzyramkowy potrzebuje **reference frame buffer**.
1080p 4:2:0 = ~3.1 MB na klatke, a K325T ma ~2 MB BRAM -> **wymusza DDR3 na
PCB**. To jest zasadnicza zmiana architektury plyty, ktorej MJPEG nie wymaga.

Kandydaci otwartoźródłowi do oceny:
- `github.com/openasic-org/xk265`
- `ultravideo.fi/uvgkvazaarhw.html` (uwaga: Kvazaar to znany **enkoder** -
  do zweryfikowania, czy HW jest dekoderem, bo enkoder jest tu bezuzyteczny)

Warto tez rozwazyc srodek: **VESA DSC** - kompresja zaprojektowana dokladnie
pod strumien display, intra-only (bez DDR), niskie opoznienie, ~3:1.

## Ocena wstepna (do domkniecia po wynikach rozeznania)

Po korektach z 2026-08-29 bilans wyglada zupelnie inaczej niz w pierwszej
wersji tego dokumentu. Dwa argumenty "przeciw" upadly (cena ukladu, brak
darmowego toolchaina), wiec zostaje:

**Za:**
- uklad juz jest, za 100 zl
- zasoby: ~16x logiki i ~17x BRAM wzgledem GW2AR-18 - dekoder przestaje byc
  ryzykiem, framebuffer/bufory pasm staja sie mozliwe
- IDELAYE2 rozwiazuje wprost problem probkowania DQ (koniec z negedge i WARN PR1014)
- piny: koniec z budzetem "zapas 1 pin" i oddawaniem flasha
- otwiera 3 monitory i wyzsze tryby, czego GW2AR-18 nie udzwignie

**Przeciw:**
- **BGA900 z wylutu**: reballing, 8-10 warstw PCB, montaz nie do zrobienia w domu
- **zasilanie**: 810 mA spoczynkowo na VCCINT, ICCINTMIN ~1.4 A, sekwencjonowanie
  5 szyn + osobne szyny GTX z filtrami LC. To przebudowa calej sekcji zasilania.
- **openXC7 to nie Vivado**: slabszy model timingu, GTX na Kintexie swiezy
  i czesciowo dzialajacy (CPLL only, PR #88 z kwietnia 2026), brak wsparcia
  twardych blokow typu PCIe
- caly kod PnR/skryptow z IRIS do przepisania

**Wstepna rekomendacja:** uklad jest kupiony i toolchain istnieje, wiec
przeniesienie **przestalo byc nieuzasadnione** - ale decyzja powinna zapasc
na podstawie tego, ktora z opcji A-D faktycznie ma sens. Jesli okaze sie,
ze zaden realny kanal >5 Gbps nie jest osiagalny, a dekoder miedzyramkowy
wymaga DDR i tak - to warto policzyc, czy nie prosciej zrobic **dwa osobne
urzadzenia na GW2AR** niz jedno na Kintexie.

## Czego brakuje do pelnej oceny

- **DS180** (7 Series Overview) - liczby LUT/FF/BRAM/DSP/GTX dla K325T
- **UG475** (7 Series Packaging) - ile dokladnie user I/O i par LVDS w FFG900
- **UG476** (GTX/GTH) - wymagania filtrow zasilania GTX
- wyniki rozeznania A-D (agenci w toku, 2026-08-29)
