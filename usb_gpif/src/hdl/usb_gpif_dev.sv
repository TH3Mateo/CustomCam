`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif_dev - wariant bring-up odbiornika GPIF II na XC7K325T.
//
// Instancjonuje rdzen usb_gpif i KONSUMUJE strumien wewnatrz FPGA, zamiast
// wyprowadzac go na piny - tak samo jak wariant Gowin (patrz
// old/usb_gpif/src/hdl/usb_gpif_dev.sv). Na K325T (400 I/O) powod "przekracza
// budzet obudowy" juz nie obowiazuje, ale sens testu zostaje: sprawdzic tor
// USB->FPGA na sprzecie bez analizatora logicznego, zanim dolozy sie dekoder
// MJPEG.
//
// RÓŻNICA WOBEC WERSJI GOWIN: brak placeholderow LVDS/EDID. Tamte istnialy
// wylacznie po to, zeby sprawdzic budzet pinow QN88 przed zaprojektowaniem
// PCB - na K325T eDP idzie przez GTX (dp_tx_subsystem + vid_phy_controller),
// nie przez zwykle GPIO, wiec ten test nie ma tu zastosowania. Budzet GTX to
// osobny, juz zmierzony temat (.claude/WYNIKI_toolchain.md).
//
// IDELAYCTRL: wymagany DOKLADNIE RAZ na kazdy bank I/O uzywajacy IDELAYE2.
// usb_gpif_rx (patrz jego naglowek) go NIE instancjonuje - kalibrator jest
// tutaj, na poziomie topu, bo jeden IDELAYCTRL obsluguje wszystkie IDELAYE2
// w banku.
//
// DO ZWERYFIKOWANIA PRZED SYNTEZA: czestotliwosc idelay_refclk. Z pamieci
// (UG471, nie mam lokalnie pliku do zacytowania) wymagane 200 MHz +-10 MHz
// dla 7-series - NIE brac tego jako pewnika, sprawdzic w UG471 albo przez
// DRC Vivado (report_drc zglosi, jesli REFCLK jest poza zakresem) przed
// pierwsza synteza tego modulu. Nie mozna zasilic z clk_core (100 MHz) -
// stad osobny port i drugi PLL/MMCM na PCB albo dodatkowe wyjscie z rPLL.
////////////////////////////////////////////////////////////////////////////////
module usb_gpif_dev (
    input  wire        clk,        // domena rdzenia = zrodlo PCLK, 100 MHz
    input  wire        idelay_refclk, // 200 MHz, WYMOG IDELAYCTRL (UG471)
    input  wire        reset,

    // --- GPIF II do FX3 ---
    input  wire [31:0] DQ,
    input  wire        FLAG_EMPTY,
    output wire        SLRD_N,
    output wire        SLOE_N,

    // --- Diagnostyka (LED / analizator) ---
    output wire        led_stream_ok,   // wzorzec ciagly, tor dziala
    output wire        led_error        // wykryto nieciaglosc lub przepelnienie
);

    // ------------------------------------------------------------------------
    // Kalibrator IDELAY - jeden na bank, wspolny dla wszystkich 32 IDELAYE2
    // w usb_gpif_rx. RDY sygnalizuje zakonczenie kalibracji startowej
    // (ok. 4 us wg UG471) - reset ukladu trzymany, dopoki RDY=0, zeby
    // pierwsze probkowanie DQ nie trafilo na niekalibrowane opoznienie.
    // ------------------------------------------------------------------------
    wire idelayctrl_rdy;

    IDELAYCTRL u_idelayctrl (
        .REFCLK(idelay_refclk),
        .RST   (reset),
        .RDY   (idelayctrl_rdy)
    );

    wire reset_sync = reset || !idelayctrl_rdy;

    wire [31:0] data;
    wire        valid;
    wire        overflow;
    wire [usb_gpif_pkg::FIFO_ADDR_BITS:0] level;

    // Odbieramy bez przerwy - konsument nadaza zawsze.
    usb_gpif u_core (
        .clk         (clk),
        .reset       (reset_sync),
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

    // --- Checker wzorca: kolejne slowa musza rosnac o 1 (bez zmian wobec Gowin) ---
    logic [31:0] expect_r;
    logic        started_r;
    logic        error_r;
    logic [23:0] ok_cnt_r;

    always_ff @(posedge clk) begin
        if (reset_sync) begin
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

endmodule
