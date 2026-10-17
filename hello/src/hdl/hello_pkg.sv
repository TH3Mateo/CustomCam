`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// hello_pkg - stale i typy modulu testowego toolchainu.
//
// Ten pakiet NIE jest potrzebny funkcjonalnie - migacz LED obylby sie bez
// niego. Istnieje po to, zeby przepuscic przez Vivado 2017.4 i XSim DOKLADNIE
// te konstrukcje SystemVerilog, ktorych uzywa docelowy kod w old/usb_gpif/:
//
//   package + import ...::*     <- usb_gpif_pkg.sv, import w naglowku modulu
//   typedef enum logic [1:0]    <- rd_state_t (S_IDLE/S_READ/S_DRAIN)
//   localparam int unsigned     <- DATA_WIDTH, RD_LATENCY, FIFO_DEPTH
//
// Jesli ktorejs z nich toolchain nie strawi, dowiadujemy sie na 50 liniach
// kodu, a nie w polowie portu dzialajacego modulu.
////////////////////////////////////////////////////////////////////////////////
package hello_pkg;

  // Zegar wejsciowy. Wartosc wstepna - plyty jeszcze nie ma, wiec sluzy
  // wylacznie do wyliczenia dzielnika i do create_clock w .xdc.
  localparam int unsigned CLK_FREQ_HZ = 100_000_000;

  // Migotanie ~1 Hz. Szerokosc licznika liczona z czestotliwosci, a nie
  // wpisana na sztywno - sprawdza, czy synteza radzi sobie z $clog2 w
  // wyrazeniu localparam (uzywane w usb_gpif_pkg.sv przy FIFO_ADDR_BITS).
  localparam int unsigned BLINK_DIV     = CLK_FREQ_HZ / 2;
  localparam int unsigned BLINK_CNT_W   = $clog2(BLINK_DIV);

  // Szerokosc licznika testowego wystawianego na LED.
  localparam int unsigned COUNT_WIDTH = 4;

  // Automat - odpowiednik rd_state_t z usb_gpif_pkg.sv. Trzy stany, kodowanie
  // jawne na logic [1:0], zeby sprawdzic wnioskowanie typu wyliczeniowego
  // przez synteze i symulator.
  typedef enum logic [1:0] {
    S_IDLE,   // po resecie, czeka na zwolnienie
    S_RUN,    // licznik pracuje
    S_HOLD    // pauza - dowod, ze przejscia stanow dzialaja
  } hello_state_t;

endpackage
