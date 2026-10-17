`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif - rdzen odbioru strumienia USB3.0 z CYUSB3014 (FX3) przez GPIF II.
//
// Sklada odbiornik (usb_gpif_rx) z buforem elastycznosci (usb_gpif_fifo) i
// wystawia strumien 32-bitowy z handshakiem valid/ready dla dekodera MJPEG.
//
//   FX3 --DQ[31:0]--> usb_gpif_rx --> usb_gpif_fifo --> data_o/valid_o/ready_i
//       <--SLRD#/SLOE#--    ^                |
//       --FLAG_EMPTY--------+                v
//                                       almost_full (hamowanie z wyprzedzeniem)
//
// ZEGAR: caly modul pracuje w domenie clk, ktora jest JEDNOCZESNIE zrodlem PCLK
// podawanego do FX3 (PCLK_O). Nie ma tu zadnego CDC - to byl glowny powod
// wyboru "PCLK generuje FPGA". Szczegoly i budzet czasowy: usb_gpif_rx.sv.
//
// Przepustowosc: 32 bity x 100 MHz = 3200 Mbit/s = 400 MB/s (sufit GPIF II).
// Realnie ogranicza USB 3.0 po stronie FX3: ~3000 Mbit/s = 375 MB/s.
//
// FX3 konfiguruje MIKROKONTROLER na PCB, nie FPGA. Ten modul nie zna momentu,
// w ktorym FX3 stanie sie gotowy - i nie musi: przy braku danych FLAG_EMPTY
// trzyma odczyt wstrzymany, bez zawieszania sie i bez bledu.
////////////////////////////////////////////////////////////////////////////////
module usb_gpif
    import usb_gpif_pkg::*;
#(
    // Przekazane w dol do usb_gpif_rx - patrz naglowek tamtego pliku.
    // Wartosc do kalibracji na sprzecie (IODELAY na DQ), nie zgadywana.
    parameter int unsigned IDELAY_TAPS = 16
) (
    input  wire                   clk,       // domena rdzenia = zrodlo PCLK
    input  wire                   reset,     // synchroniczny, aktywny wysoko

    // --- Interfejs fizyczny do FX3 ---
    input  wire [DATA_WIDTH-1:0]  DQ,
    input  wire                   FLAG_EMPTY,
    output wire                   SLRD_N,
    output wire                   SLOE_N,

    // --- Strumien do dekodera MJPEG ---
    output wire [DATA_WIDTH-1:0]  data_o,
    output wire                   valid_o,
    input  wire                   ready_i,

    // --- Diagnostyka ---
    output wire [FIFO_ADDR_BITS:0] fifo_level_o,
    output wire                    overflow_o
);

    wire [DATA_WIDTH-1:0] rx_data;
    wire                  rx_valid;
    wire                  almost_full;

    usb_gpif_rx #(
        .IDELAY_TAPS(IDELAY_TAPS)
    ) u_rx (
        .clk          (clk),
        .rst          (reset),
        .DQ           (DQ),
        .FLAG_EMPTY   (FLAG_EMPTY),
        .SLRD_N       (SLRD_N),
        .SLOE_N       (SLOE_N),
        .data_o       (rx_data),
        .valid_o      (rx_valid),
        .almost_full_i(almost_full),
        .state_o      ()
    );

    usb_gpif_fifo u_fifo (
        .clk          (clk),
        .rst          (reset),
        .wr_data_i    (rx_data),
        .wr_valid_i   (rx_valid),
        .almost_full_o(almost_full),
        .rd_data_o    (data_o),
        .rd_valid_o   (valid_o),
        .rd_ready_i   (ready_i),
        .level_o      (fifo_level_o),
        .overflow_o   (overflow_o)
    );

endmodule
