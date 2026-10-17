`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif_pkg - wspolne stale i typy odbiornika GPIF II (CYUSB3014 / FX3).
//
// Zrodla liczb: CYUSB3014.pdf, Tabela 13 (GPIF II Timing Parameters in
// Synchronous Mode) i Tabela 15 (Synchronous Slave FIFO Parameters).
////////////////////////////////////////////////////////////////////////////////
package usb_gpif_pkg;

  // --- Magistrala ---
  // GPIF II w trybie 32-bit. Przy 32 bitach FX3 udostepnia 14 pinow kontrolnych
  // (przy 8/16 bitach - 16), ale my uzywamy tylko SLRD#/SLOE#/FLAG - patrz
  // .claude/PINOUT.md, redukcja 44 -> 35 pinow.
  localparam int unsigned DATA_WIDTH = 32;

  // --- Zegar ---
  // PCLK 100 MHz = sufit GPIF II (Tabela 13: "Interface clock frequency, max 100
  // MHz", tCLK min 10 ns). Generowany przez FPGA z PLL - patrz naglowek
  // usb_gpif_rx.sv, punkt o wyborze zrodla zegara.
  localparam int unsigned PCLK_FREQ_HZ  = 100_000_000;
  localparam int unsigned PCLK_PERIOD_NS = 10;

  // --- Latencja odczytu ---
  // Droga slowa od zamowienia do wyjscia odbiornika, w cyklach PCLK:
  //   +1  FX3 przetwarza SLRD# i wystawia dane po tCO=7ns (Tabela 15) -> N+1
  //   +1  rejestr wejsciowy FPGA na zboczu opadajacym
  //   +1  przepisanie do domeny posedge
  // Automat MUSI opoznic 'valid' o DOKLADNIE tyle samo cykli - rozjazd o jeden
  // daje przesuniety strumien i smieci na poczatku (potwierdzone w symulacji).
  // Dlatego jawny parametr, a nie liczba wpisana w kod.
  localparam int unsigned RD_LATENCY = 2;

  // --- FIFO ---
  // 512 slow x 32 bity = 16 kbit = 1 BSRAM (z 46 dostepnych w GW2AR-18).
  localparam int unsigned FIFO_DEPTH     = 512;
  localparam int unsigned FIFO_ADDR_BITS = 9;   // $clog2(FIFO_DEPTH)

  // Prog wstrzymania odczytu. FLAG ma tCFLG=8ns propagacji (Tabela 15), a odczyt
  // jest w locie przez RD_LATENCY cykli - od decyzji "stop" do faktycznego
  // zatrzymania mija kilka cykli, w ktorych dane wciaz naplywaja. Margines musi
  // pokryc te cykle, inaczej FIFO sie przepelni i zgubimy slowa.
  localparam int unsigned ALMOST_FULL_MARGIN = 8;

  // --- Stany automatu odczytu ---
  typedef enum logic [1:0] {
    S_IDLE,   // czekanie na dane w FX3 i miejsce w FIFO
    S_READ,   // SLRD#/SLOE# aktywne, strumien leci
    S_DRAIN   // SLRD# zdjete, odbieranie slow bedacych juz w locie
  } rd_state_t;

endpackage
