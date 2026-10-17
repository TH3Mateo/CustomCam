# Budzet GPIO - GW2AR-18 QN88

> **STAN 2026-08-28 (zmierzony PnR): 61 z 62 pinow, zapas 1.**
> Miesci sie: 32 DQ + 4 sterowanie GPIF + 20 LVDS (10 par TLVDS) + clk + reset
> + I2C EDID (2). Twardy limit narzedzia: **61 zwyklych I/O + 1 RECONFIG_N**.
> Wymaga oddania MSPI i SSPI na GPIO -> **brak flash**, programowanie przez JTAG.

> **POTWIERDZONE PnR 2026-08-28: caly docelowy pinout MIESCI SIE w QN88.**
> 59 pinow rozmieszczonych, bitstream wygenerowany, 0 naruszen timingu.
> **Ale wymaga oddania MSPI (59-62) I SSPI (52,54,55,56) na GPIO**, czyli
> **rezygnacji z flash** - programowanie tylko przez JTAG (5,6,7,8).
> Szczegoly: `.claude/WYNIKI_usb_gpif.md`.

> **KOREKTA 2026-08-27 po pierwszym PnR.** Narzedzie Gowin zglasza (PA2024):
> *"resource limit **53 regular I/Os** and 1 RECONFIG_N, you can also use
> 4 JTAG, 4 SSPI and 4 MSPI by configuring Dual-Purpose Pin as regular I/Os"*.
> Realnie dostepne przy zachowaniu JTAG + flash MSPI: **57 pinow**, czyli
> DOKLADNIE tyle, ile potrzeba (35+20+2). **Zapas = 0.**
> Dodatkowo piny 52,54,55,56 (SSPI) sa odrzucane mimo `-use_sspi_as_gpio 1`.
> Szczegoly i pomiary: `.claude/WYNIKI_usb_gpif.md`.

Zywy dokument. Aktualizowac przy kazdym dolozeniu modulu.
Sprzet nie istnieje - pinout NIE jest utrwalony, numery pinow w .cst sa wstepne.

## Stan biezacy

```
Pula user I/O QN88                    66
  - JTAG  (5, 6, 7, 8)                 4   zarezerwowane, programowanie
  - MSPI  (59, 60, 61, 62)             4   zarezerwowane, flash (FPGA master)
                                     ----
Dostepne (w tym 3 piny SSPI)          58

ZAPOTRZEBOWANIE:
  GPIF II DQ[31:0]                    32
  GPIF II PCLK      (WYJSCIE -> FX3)   1
  GPIF II SLRD#                        1
  GPIF II FLAG_EMPTY                   1
                                     ---
  razem GPIF II (RX-only)             35

  LVDS 2x (4 pary danych + 1 zegar)   20
  clk100M (WEJSCIE <- generator PCB)   1
  reset                                1
                                     ---
  RAZEM                               57

ZAPAS                                  1 pin
```

**UWAGA: PCLK i clk100M to DWA ROZNE PINY.**
- `clk100M` - wejscie, zrodlo systemowe z fizycznego generatora na PCB
- `PCLK`    - wyjscie, 100 MHz z PLL FPGA do FX3 (patrz DECYZJE.md §2)

QN88 ma 22 pary True LVDS - potrzeba 10. Mieści się.

## Piny konfiguracyjne sa wliczone w 66

`GW2AR_application_note.pdf` (UG229), Tabela 2-3, przypis [1]:
> "Single end/Differential/LVDS I/O quantity **include CLK pins, and download pins**."

Piny konfiguracyjne sa dwufunkcyjne - w tabeli pinow wystepuja jako zwykle I/O
z aliasem:

| Funkcja | Nazwa w tabeli pinow                                            | Pin QN88     |
|---------|-----------------------------------------------------------------|--------------|
| JTAG    | `IOR25A/TDO`, `IOR25B/TMS`, `IOR26A/TCK`, `IOR26B/TDI`          | 8, 5, 6, 7   |
| MSPI    | `IOR33A/MI/D7`, `IOR33B/MO/D6`, `IOR34A/MCS_N/D5`, `IOR34B/MCLK/D4` | 62,61,60,59 |
| SSPI    | `IOR36A/SO/D1`, `IOR36B/SSPI_CS_N/D0`, `IOR35A/FASTRD_N/D3`     | 56, 55, 57   |

**MSPI i SSPI to ROZLACZNE grupy pinow.** Trzymanie flasha na MSPI nie koliduje
z uzyciem SSPI jako GPIO.

### Jak uwolnic piny SSPI

Decyduje `set_option -use_sspi_as_gpio 1` w **`run_pnr.tcl`** (generowanym przez
`generate_pnr_script.py`), a NIE wpis `set SSPI regular_io` w `device.cfg`.

Zweryfikowane w IRIS: ma te opcje wlaczona (`generate_pnr_script.py:106`) i dzieki
temu prowadzi `MOSI2` na pinie 55 i `CS_N2` na 56. W `device.cfg` IRIS ma
`set SSPI regular_io = false` - `true` widoczne w tym pliku to komentarz-podpowiedz
toolchainu, nie ustawienie.

## Redukcja pinow GPIF II: 44 -> 35

Tor jest **wylacznie odbiorczy** (FX3 -> FPGA), wiec znika cala polowa zapisowa.

| Sygnal              | Pelny | Min | Uzasadnienie ciecia |
|---------------------|------:|----:|---------------------|
| `DQ[31:0]`          |    32 |  32 | nieredukowalne |
| `PCLK`              |     1 |   1 | nieredukowalne |
| `SLRD#`             |     1 |   1 | konieczne |
| `SLOE#`             |     1 |   0 | **zwarte z SLRD# na PCB** - przy czystym odczycie identyczny przebieg |
| `SLCS#`             |     1 |   0 | **na stale do GND** - jedno urzadzenie na magistrali |
| `SLWR#`, `PKTEND#`  |     2 |   0 | **tylko dla zapisu FPGA->FX3**, nie wystepuje |
| `A[1:0]`            |     2 |   0 | **na stale 0** - jeden socket, przelaczanie watkow w automacie GPIF II |
| `FLAGA..D`          |     4 |   1 | **1 flaga dedykowana** (empty biezacego watku) wystarczy do flow control |
| **RAZEM**           |**44** |**35**| **oszczednosc 9 pinow** |

### Ryzyka tych ciec
- Zwarcie SLOE#+SLRD# usuwa mozliwosc trzymania danych na magistrali bez
  inkrementacji wskaznika FIFO (brak "peek"). Sterownik musi to respektowac.
  Akceptowalne dla strumienia ciaglego.
- Jedna flaga zamiast dwoch wyklucza bezprzerwowe przelaczanie socketow (brak
  podgladu drugiego watku) - kosztuje ~3 cykle martwe na granicy bufora DMA.
  Przy buforze 4 kB to 0.3% przepustowosci, nieistotne.
- `SLOE#` zostaje osobnym portem w RTL mimo zwarcia na PCB - dzieki temu decyzja
  jest odwracalna bez zmian w kodzie, wystarczy `.cst`.

## Diody bring-up NIE zajmuja budzetu docelowego

`led_stream_ok` / `led_error` sluza wylacznie do bring-upu (checker wzorca
testowego). W wersji produkcyjnej ich nie ma, wiec **ich piny przejmuje I2C
EDID** - potwierdzone PnR: 61 portow, 0 naruszen timingu, `Inout Buf = 2`.

I2C wymaga `OPEN_DRAIN=ON` (pull-upy na PCB). W RTL musi byc prawdziwy inout
(`oe ? 1'b0 : 1'bz`) z odczytem wchodzacym do logiki - inaczej synteza zwija
linie do zwyklego wyjscia i `Inout Buf = 0`.

## Skad wziac zapas, gdy 1 pin okaze sie za malo

Kolejnosc od najtanszej:

| Zrodlo                                   | Zysk | Koszt |
|------------------------------------------|-----:|-------|
| Rezygnacja z flash MSPI (JTAG-only)      |   +4 | programowanie przez JTAG za kazdym razem |
| `reset` z wewnetrznego POR zamiast pinu  |   +1 | brak zewnetrznego resetu |
| LVDS 18 bpp (3 pary danych zamiast 4)    |   +4 | kolor 18-bit zamiast 24-bit |

Przy 1 pinie zapasu **kazdy** dodatkowy sygnal (I2C do EDID, dioda statusowa,
sygnal "FX3 gotowy" z MCU) wymaga siegniecia po ktoras z powyzszych pozycji.

**Decyzja: na razie przyjmujemy brak zapasu.** Wracamy do tej tabeli dopiero
gdy okaze sie potrzebny.

## Czego NIE ma w budzecie (i dlaczego)

- **Konfiguracja FX3** - zajmuje sie nia **osobny mikrokontroler na PCB**.
  FPGA nie bootuje FX3, nie laduje jego firmware'u i nie potrzebuje do niego
  I2C/SPI. Stad brak pozycji na te sygnaly.
- **UART debug** - pominiety na tym etapie.
