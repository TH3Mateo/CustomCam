`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// edp_pkg - wspolne stale modulu wyjscia eDP (dp_tx_subsystem + GTX PHY).
//
// Kontekst toru: usb_gpif -> dekoder MJPEG -> edp -> zlacze 30-pin matrycy.
// Ten modul NIE zna kompresji - wejsciem jest zdekompresowany strumien
// pikseli (AXI4-Stream video), wyjsciem sygnaly fizyczne DP/eDP na GTX.
//
// Docelowo: 3 NIEZALEZNE tory (3 surowe matryce eDP, kazda wlasny link
// training po AUX - to NIE jest DP Multi-Stream, patrz .claude/WYNIKI_toolchain.md
// "KOREKTA: MST nie nadaje sie do surowych matryc eDP").
//
// Zrodla liczb: PG199 (DisplayPort TX Subsystem), UG476 (GTX Transceivers),
// zmierzone lokalnie w Vivado 2017.4 dla xc7k325tffg676-2 (.claude/WYNIKI_toolchain.md).
////////////////////////////////////////////////////////////////////////////////
package edp_pkg;

  // --- Link eDP ---
  // 2 linie danych na matryce (SST, HBR) - zmierzone: 6046 LUT / tor,
  // 6x GTX dla 3 torow z 8 dostepnych w FFG676. 4 linie zwiekszylyby
  // przepustowosc, ale 3x4=12 kanalow NIE MIESCI SIE (tylko 8 dostepnych).
  localparam int unsigned LANE_COUNT = 2;

  // Line rate. RBR (1.62) start negocjacji, HBR (2.7) docelowy tryb pracy -
  // 1080p60 24bpp = 3.56 Gb/s, 2 linie x 2.7 Gb/s = 5.4 Gb/s surowo,
  // 4.32 Gb/s po 8b/10b -> zapas 21%.
  localparam real RBR_GBPS = 1.62;
  localparam real HBR_GBPS = 2.70;

  // --- Piksele ---
  localparam int unsigned BITS_PER_COLOR = 8;    // 24bpp docelowo
  localparam int unsigned PIXEL_MODE     = 4;    // pikseli/takt w dp_tx_subsystem

  // --- Liczba niezaleznych torow (matryc) ---
  // 3 = cel projektu. Budzet GTX: 2 quady x 4 kanaly = 8 dostepnych w FFG676,
  // 3 tory x 2 linie = 6 uzytych. KAZDY tor to NIEZALEZNA instancja
  // dp_tx_subsystem + wlasny AUX + wlasny link training.
  localparam int unsigned NUM_PANELS = 3;

  // --- Quady GTX (FFG676) ---
  // Tylko 2 quady wyprowadzone do pinow (banki MGT 115, 116) - reszta
  // kanalow istnieje w krzemie, ale nie ma kulek w tej obudowie.
  // Rozklad 3 torow (6 kanalow) na 2 quady (8 kanalow): NIE rowny,
  // jeden quad niesie 2 tory (4 kanaly, pelny), drugi 1 tor (2 kanaly,
  // polowa quadu wolna - do wykorzystania pod przyszly 4. tor albo USB).
  localparam int unsigned QUAD0_PANELS = 2;  // kanaly 0-3 tego quadu
  localparam int unsigned QUAD1_PANELS = 1;  // kanaly 0-1 tego quadu, 2-3 wolne

endpackage
