# LVDS -> eDP: konwersja (rozeznanie 2026-08-28)

## Problem

Panele FullHD z LVDS sa wypierane przez eDP - coraz trudniej je kupic.
Pytanie: czy da sie sterowac panelem eDP z GW2AR?

## eDP bezposrednio z FPGA: NIEMOZLIWE

Blokada jest w warstwie fizycznej, nie w ilosci logiki:

| | Mbps/lane |
|---|---:|
| GW2AR, sufit gearboxa OSER10 | **1200** |
| eDP RBR - najwolniejszy tryb jaki ISTNIEJE | **1620** |
| eDP HBR | 2700 |

Najwolniejszy dopuszczalny tryb eDP przekracza mozliwosci ukladu o 35%.
DisplayPort nie definiuje nic wolniejszego niz RBR, wiec nie da sie "zejsc
nizej" tak jak przy LVDS (gdzie mozna zmniejszyc bpp).

Dodatkowo GW2AR **nie ma transceiverow** - przeszukanie DS226 pod katem
`transceiver`, `SerDes`, `8b/10b`, `PCIe`, `SATA` daje ZERO trafien. eDP
wymaga 8b/10b, CDR po stronie RX, kontrolowanego swing/pre-emfazy oraz
dwukierunkowego kanalu AUX do link training.

## Rozwiazanie: mostek LVDS -> eDP

**Wiekszosc mostkow na rynku to eDP -> LVDS** (odwrotny kierunek, dla
starych paneli LVDS przy nowych GPU): NXP PTN3460/PTN3460I, Parade PS8625,
PS8615, PS8627V. **Te NIE nadaja sie** do naszego zastosowania.

### LT8911EX (Lontium) - wlasciwy kierunek

Potwierdzone z oryginalnego Product Brief R1.1:

| Parametr | Wartosc |
|---|---|
| Kierunek | **LVDS -> eDP** (tego szukamy) |
| Wejscie LVDS | single/dual-port, 1 clk + do 8 par danych, **max 1.2 Gb/s na pare** |
| | VESA i JEIDA, 6-bit lub 8-bit na kanal, De-SSC |
| Pasmo wejsciowe | max 9.6 Gbps |
| Wyjscie eDP | **eDP 1.4**, 1/2/4 lane, RBR (1.62) lub HBR (2.7 Gbps) |
| Zasilanie | pojedyncze **1.8 V** |
| Obudowa | QFN64 9x9 mm, 0.5 mm raster |
| Temperatura | -40..+85 C |
| Ekstra | PWM backlight, MCCS over AUX, opcjonalny SSC |

**Nasz przypadek miesci sie z zapasem:**
- wyjscie FPGA: 1040 Mb/s na pare < 1.2 Gb/s limitu LT8911EX (zapas 13%)
- 1080p60 24bpp = 3.56 Gbps payload; wystarczy RBR x4 (5.18 Gbps uzytecznie)
  albo HBR x2 (4.32 Gbps). RBR x2 (2.59 Gbps) NIE wystarczy.

**Po stronie FPGA nic sie nie zmienia** - nadal wystawiamy LVDS 4-lane.
Pinout z `.claude/PINOUT.md` zostaje bez zmian.

### Do zweryfikowania przed decyzja

- **Dostepnosc i MOQ** - Lontium to chinski producent, tray 2600 szt.
  Brak potwierdzenia dostepnosci u europejskich dystrybutorow.
- **"ADVANCE INFORMATION - CONFIDENTIAL"** w naglowku brief - pelna karta
  katalogowa moze wymagac NDA.
- **Konfiguracja** - brief nie mowi, czy wymaga I2C od MCU po starcie.
  Na PCB jest juz mikrokontroler (konfiguruje FX3), wiec moglby obsluzyc
  tez ten uklad - do potwierdzenia.
- **Zasilanie 1.8V** - dodatkowa szyna na PCB.
- **Alternatywy**: LT8911 (wersja podstawowa), LT9211C - do sprawdzenia,
  czy obsluguja ten kierunek. Istnieje otwarty sterownik Linux
  (github.com/aystshen/lontium_lt8911_driver) - przydatny jako dokumentacja
  sekwencji inicjalizacji przez I2C.

## Wniosek

Przejscie na panele eDP jest realne, ale **wylacznie przez mostek** -
nie bezposrednio z FPGA. LT8911EX pasuje parametrami. Glowne ryzyko to
dostepnosc/zakupy, nie technika.

Alternatywa strategiczna: FPGA z prawdziwymi transceiverami (Lattice
CrossLink-NX, Xilinx Artix-7 GTP) - ale to zmiana calej platformy.
