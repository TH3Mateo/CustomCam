////////////////////////////////////////////////////////////////////////////////
// usb_gpif_dev - wariant bring-up odbiornika GPIF II.
//
// Instancjonuje rdzen usb_gpif i KONSUMUJE strumien wewnatrz FPGA, zamiast
// wyprowadzac go na piny. Powod jest twardy: rdzen ma 32-bitowe wyjscie danych
// + sterowanie, co razem z 35 pinami GPIF przekracza obudowe QN88 (narzedzie
// Gowin: "The number(82) of ports exceeds the resource limit 53 regular I/Os").
// Docelowo strumien i tak trafia do dekodera MJPEG wewnatrz ukladu.
//
// Konsument to checker wzorca testowego: FX3 wysyla licznik inkrementujacy,
// a ten modul sprawdza ciaglosc i wystawia wynik na 2 piny diagnostyczne.
// Dzieki temu na sprzecie widac od razu, czy tor USB->FPGA dziala, bez
// analizatora logicznego.
////////////////////////////////////////////////////////////////////////////////
module usb_gpif_dev
    import usb_gpif_pkg::*;
#(
    // Liczba par danych na wyswietlacz. 4 = 24bpp (docelowo), 3 = 18bpp.
    parameter int unsigned LVDS_LANES = 4
) (
    input  wire        clk,
    input  wire        reset,

    // --- GPIF II do FX3 ---
    input  wire [31:0] DQ,
    input  wire        FLAG_EMPTY,
    output wire        SLRD_N,
    output wire        SLOE_N,

    // --- Diagnostyka (LED / analizator) ---
    output wire        led_stream_ok,   // wzorzec ciagly, tor dziala
    output wire        led_error,       // wykryto nieciaglosc lub przepelnienie

    // --- ZAJETOSC PINOW POD DOCELOWY SYSTEM (placeholder) ---
    // Te wyjscia nie licza sie funkcjonalnie - istnieja WYLACZNIE po to, zeby
    // .cst opisywal docelowy pinout i zeby PnR potwierdzil, ze komplet sygnalow
    // da sie fizycznie rozmiescic w QN88 zanim powstanie PCB.
    // Docelowo: 2 x single-link LVDS 4-lane 24bpp = 2 x (4 pary danych + 1 zegar).
    //
    // Pary roznicowe realizuje prymitywa TLVDS_OBUF (jeden sygnal I -> para
    // O/OB), a NIE dwa osobne porty LVCMOS. W .cst deklaruje sie wtedy tylko
    // pin dodatni z IO_TYPE=LVDS25; pin ujemny narzedzie przydziela samo.
    output wire [LVDS_LANES-1:0] LVDS0_D_P,       // wyswietlacz 0: 4 pary danych
    output wire [LVDS_LANES-1:0] LVDS0_D_N,
    output wire        LVDS0_CLK_P,     // wyswietlacz 0: para zegara
    output wire        LVDS0_CLK_N,
    output wire [LVDS_LANES-1:0] LVDS1_D_P,       // wyswietlacz 1: 4 pary danych
    output wire [LVDS_LANES-1:0] LVDS1_D_N,
    output wire        LVDS1_CLK_P,     // wyswietlacz 1: para zegara
    output wire        LVDS1_CLK_N,

    // --- I2C do odczytu EDID z wyswietlaczy (placeholder) ---
    // Na pinach po diodach bring-up. W wersji produkcyjnej diod nie ma, wiec
    // te dwa piny sa wolne. I2C jest OPEN-DRAIN (magistrala z pull-upami na
    // PCB), stad inout + stale zwolnienie linii w tym placeholderze.
    inout wire         EDID_SCL,
    inout wire         EDID_SDA
);

    wire [31:0] data;
    wire        valid;
    wire        overflow;
    wire [FIFO_ADDR_BITS:0] level;

    // Odbieramy bez przerwy - konsument nadaza zawsze.
    usb_gpif u_core (
        .clk         (clk),
        .reset       (reset),
        .DQ          (DQ),
        .FLAG_EMPTY  (FLAG_EMPTY),
        .SLRD_N      (SLRD_N),
        .SLOE_N      (SLOE_N),
        .data_o      (data),
        .valid_o     (valid),
        .ready_i     (1'b1),
        .fifo_level_o(level),
        .overflow_o  (overflow)
    );

    // --- Checker wzorca: kolejne slowa musza rosnac o 1 ---
    logic [31:0] expect_r;
    logic        started_r;
    logic        error_r;
    logic [23:0] ok_cnt_r;

    always_ff @(posedge clk) begin
        if (reset) begin
            expect_r  <= 32'd0;
            started_r <= 1'b0;
            error_r   <= 1'b0;
            ok_cnt_r  <= 24'd0;
        end else if (valid) begin
            // Pierwsze slowo ustala punkt odniesienia - nie znamy stanu
            // licznika FX3 w chwili startu FPGA.
            if (!started_r) begin
                started_r <= 1'b1;
                expect_r  <= data + 32'd1;
            end else begin
                if (data != expect_r) error_r <= 1'b1;
                else                  ok_cnt_r <= ok_cnt_r + 1'b1;
                expect_r <= data + 32'd1;
            end
        end
    end

    // Blysk co ~0.17s przy 100MHz - widoczny golym okiem gdy strumien plynie.
    assign led_stream_ok = ok_cnt_r[23];
    assign led_error     = error_r || overflow;

    // --- Placeholder LVDS: zajmuje piny przez PRAWDZIWE bufory roznicowe ---
    // Zrodlem sa dane ze strumienia XOR licznik, zeby synteza nie zwinela tych
    // wyjsc do stalych i faktycznie zajela piny. To wciaz placeholder: brak
    // serializacji OSER10/gearbox i timingu wideo - prawdziwy nadajnik
    // (7:1, 1039 Mbit/s na pare) powstanie osobno. Sprawdzamy TYLKO, czy
    // 10 par LVDS + reszta sygnalow da sie rozmiescic w QN88.
    logic [7:0] lvds_src_r;
    always_ff @(posedge clk) begin
        if (reset)      lvds_src_r <= 8'd0;
        else if (valid) lvds_src_r <= data[7:0] ^ ok_cnt_r[7:0];
    end

    genvar gi;
    generate
        for (gi = 0; gi < LVDS_LANES; gi = gi + 1) begin : g_lvds_data
            TLVDS_OBUF u_d0 (.O(LVDS0_D_P[gi]), .OB(LVDS0_D_N[gi]), .I(lvds_src_r[gi]));
            TLVDS_OBUF u_d1 (.O(LVDS1_D_P[gi]), .OB(LVDS1_D_N[gi]), .I(lvds_src_r[gi+4]));
        end
    endgenerate

    TLVDS_OBUF u_clk0 (.O(LVDS0_CLK_P), .OB(LVDS0_CLK_N), .I(lvds_src_r[4]));
    TLVDS_OBUF u_clk1 (.O(LVDS1_CLK_P), .OB(LVDS1_CLK_N), .I(lvds_src_r[5]));

    // Placeholder I2C - DWUKIERUNKOWY, zeby test zajmowal pin tak jak zrobi to
    // prawdziwy master: linia albo ciagnieta do zera, albo puszczona w Hi-Z
    // (stan wysoki daje pull-up na PCB). Odczyt wchodzi do rejestru, inaczej
    // synteza zwinelaby inout do zwyklego wyjscia (Inout Buf = 0 w raporcie).
    logic scl_oe_r, sda_oe_r;
    logic scl_in_r, sda_in_r;

    always_ff @(posedge clk) begin
        if (reset) begin
            scl_oe_r <= 1'b0;
            sda_oe_r <= 1'b0;
        end else begin
            scl_oe_r <= ok_cnt_r[0] ^ sda_in_r;
            sda_oe_r <= ok_cnt_r[1] ^ scl_in_r;
        end
        scl_in_r <= EDID_SCL;
        sda_in_r <= EDID_SDA;
    end

    assign EDID_SCL = scl_oe_r ? 1'b0 : 1'bz;
    assign EDID_SDA = sda_oe_r ? 1'b0 : 1'bz;

endmodule
