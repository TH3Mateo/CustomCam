`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif_rx - odbiornik strumienia z FX3 (CYUSB3014) przez GPIF II
//               w trybie Synchronous Slave FIFO, FPGA jako master.
//
// PORT NA KINTEX-7: zastepuje probkowanie na NEGEDGE (uzywane w wersji Gowin,
// patrz old/usb_gpif/src/hdl/usb_gpif_rx.sv) kalibrowanym opoznieniem wejscia
// IDELAYE2. To NIE jest kosmetyczna zmiana skladni - to inne rozwiazanie tego
// samego problemu timingu, mozliwe tylko dlatego, ze K7 ma IDELAY, a GW2AR nie.
//
// Tor jest WYLACZNIE odbiorczy (FX3 -> FPGA). Nie ma zapisu, wiec nie ma
// SLWR#/PKTEND#; SLCS# zwarty do GND na PCB, A[1:0] na stale 0.
//
// --- DLACZEGO IDELAYE2 ZAMIAST NEGEDGE (nie zmieniac bez pomiarow!) ---
// FX3 ma tCO = 7 ns max (CYUSB3014.pdf Tab. 13/15) przy okresie PCLK 10 ns.
// PCLK generuje FPGA, wiec budzet jest typu round-trip:
//     10 ns - tPD(clk FPGA->FX3) - tCO(7) - tPD(dane FX3->FPGA) - tSU
//   = 10 - 1 - 7 - 1 - 1 = 0 ns  --> proste probkowanie na posedge NIE DZIALA.
//
// Wersja Gowin obeszla to probkujac na ZBOCZU OPADAJACYM (pol okresu = 5 ns
// marginesu) - dzialalo, ale zmierzone na sprzecie ostrzezenie (WARN PR1014,
// patrz .claude/WYNIKI_usb_gpif.md) pokazalo, ze rejestr negedge trafial na
// zwykly routing zamiast siec zegarowa, co przy 100 MHz zjada wiekszosc
// marginesu skew.
//
// K7 ma dedykowany blok do DOKLADNIE tego problemu: IDELAYE2 wprowadza
// KALIBROWANE opoznienie na linii wejsciowej (krok ok. 78 ps w trybie FIXED,
// IDELAYCTRL kalibruje wzgledem REFCLK), przesuwajac dane w czasie tak, zeby
// trafily w srodek okna setup/hold NA POSEDGE - bez zmiany liczby cykli
// zegara i bez polegania na routingu negedge. To ROZWIAZUJE problem z
// WYNIKI_usb_gpif.md wprost, a nie obchodzi go.
//
// Konsekwencja dla potoku: PROBKOWANIE JEST NA POSEDGE, jeden rejestr zamiast
// dwoch (negedge+posedge) w wersji Gowin. RD_LATENCY spada z 2 na 1.
//
// --- BRAK CDC (bez zmian wzgledem Gowin) ---
// PCLK pochodzi z tego samego PLL co clk (domena rdzenia), wiec caly modul
// pracuje w jednej domenie.
////////////////////////////////////////////////////////////////////////////////
module usb_gpif_rx
    import usb_gpif_pkg::*;
#(
    // Wartosc opoznienia IDELAYE2 w trybie FIXED, jednostki ok. 78 ps (0-31).
    // Startowa: srodek zakresu. DO SKALIBROWANIA NA SPRZECIE (patrz naglowek) -
    // parametr jawny, zeby dostrojenie nie wymagalo grzebania w kodzie automatu.
    parameter int unsigned IDELAY_TAPS = 16
) (
    input  logic                   clk,          // = PCLK (ta sama domena)
    input  logic                   rst,          // synchroniczny, aktywny wysoko

    // --- Interfejs fizyczny GPIF II ---
    input  logic [DATA_WIDTH-1:0]  DQ,           // dane z FX3
    input  logic                   FLAG_EMPTY,   // 1 = sa dane, 0 = bufor pusty
    output logic                   SLRD_N,       // odczyt, aktywny nisko
    output logic                   SLOE_N,       // output enable, aktywny nisko

    // --- Strumien wyjsciowy do FIFO ---
    output logic [DATA_WIDTH-1:0]  data_o,
    output logic                   valid_o,
    input  logic                   almost_full_i, // 1 = zwalniaj, brak miejsca

    // --- Diagnostyka ---
    output rd_state_t              state_o
);

    rd_state_t state_r;
    assign state_o = state_r;

    logic rd_active_r;   // SLRD#/SLOE# aktywne w tym cyklu

    // Zamowienie slowa. Zanim odpowiadajace mu dane wroca na DQ, mija 1 cykl -
    // FX3 przetwarza SLRD# i wystawia dane po tCO (Tab. 15), IDELAYE2 przesuwa
    // je w fazie (nie w cyklach), wiec dane sa gotowe do zlapania na TYM SAMYM
    // zboczu posedge co w wersji Gowin bylby drugi rejestr. RD_LATENCY=1,
    // nie 2 - jeden stopien opoznienia mniej niz przy negedge+posedge.
    logic req_r;         // zamowienie zlozone (SLRD# aktywne)
    logic word_taken;    // dane tego zamowienia sa wlasnie na DQ

    assign req_r = rd_active_r;

    logic req_d1_r;
    always_ff @(posedge clk) begin
        if (rst) req_d1_r <= 1'b0;
        else     req_d1_r <= req_r;
    end

    assign word_taken = req_d1_r;

    // ------------------------------------------------------------------------
    // IDELAYE2 na kazdej linii DQ + jeden rejestr wejsciowy na POSEDGE.
    //
    // IDELAYCTRL (kalibrator, wspolny dla calego banku I/O) instancjonowany
    // jest NA POZIOMIE TOPU, nie tutaj - jeden kalibrator obsluguje wiele
    // IDELAYE2 w tym samym banku, wiec instancjonowanie go w kazdej instancji
    // usb_gpif_rx byloby bledem (wielokrotna kalibracja tego samego banku).
    // Port CNTVALUEOUT/LD pominiety - IDELAY_VALUE stale w tej wersji
    // (tryb FIXED), dynamiczne dostrajanie to rozszerzenie na przyszlosc.
    // ------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] dq_delayed;
    logic [DATA_WIDTH-1:0] dq_r;
    logic                  vld_r;

    genvar gi;
    generate
        for (gi = 0; gi < DATA_WIDTH; gi = gi + 1) begin : g_idelay
            IDELAYE2 #(
                .IDELAY_TYPE           ("FIXED"),
                .IDELAY_VALUE          (IDELAY_TAPS),
                .HIGH_PERFORMANCE_MODE ("TRUE"),
                .SIGNAL_PATTERN        ("DATA")
            ) u_idelay (
                .IDATAIN    (DQ[gi]),
                .DATAOUT    (dq_delayed[gi]),
                .C          (1'b0),
                .CE         (1'b0),
                .INC        (1'b0),
                .LD         (1'b0),
                .LDPIPEEN   (1'b0),
                .REGRST     (1'b0),
                .CINVCTRL   (1'b0),
                .CNTVALUEIN (5'b0),
                .CNTVALUEOUT(),
                .DATAIN     (1'b0)
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        dq_r  <= dq_delayed;
        vld_r <= rst ? 1'b0 : word_taken;
    end

    // ------------------------------------------------------------------------
    // Automat. Warunek czytania: FX3 ma dane ORAZ jest gdzie je odlozyc.
    // (bez zmian wzgledem wersji Gowin - logika automatu nie zalezy od
    // sposobu probkowania DQ)
    // ------------------------------------------------------------------------
    logic can_read;
    assign can_read = FLAG_EMPTY && !almost_full_i;

    // Po zdjeciu SLRD# slowa zamowione wczesniej sa jeszcze w drodze. Stala
    // liczba cykli - droga jest z gory znana (RD_LATENCY, teraz =1 zamiast =2).
    localparam int unsigned DRAIN_CYCLES = RD_LATENCY + 1;

    logic [3:0] drain_cnt_r;
    logic       drain_done;
    assign drain_done = (drain_cnt_r == '0);

    always_ff @(posedge clk) begin
        if (rst)                     drain_cnt_r <= '0;
        else if (state_r != S_DRAIN) drain_cnt_r <= DRAIN_CYCLES[3:0];
        else if (drain_cnt_r != '0)  drain_cnt_r <= drain_cnt_r - 1'b1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r     <= S_IDLE;
            rd_active_r <= 1'b0;
        end else begin
            case (state_r)
                // Start dopiero gdy sa dane i miejsce. Brak gotowosci FX3 nie
                // jest bledem - po prostu czekamy (FX3 konfiguruje mikrokontroler
                // na PCB, FPGA nie zna momentu, w ktorym on skonczy).
                S_IDLE: begin
                    rd_active_r <= can_read;
                    if (can_read) state_r <= S_READ;
                end

                // Strumien leci. Wychodzimy gdy FX3 sie oproznil albo nasze FIFO
                // sie zapelnia.
                S_READ: begin
                    rd_active_r <= can_read;
                    if (!can_read) state_r <= S_DRAIN;
                end

                // SLRD# juz zdjete, ale slowa zamowione wczesniej sa nadal w
                // locie (RD_LATENCY cykli). Licznik nizej domyka ich odbior.
                S_DRAIN: begin
                    rd_active_r <= 1'b0;
                    if (drain_done) state_r <= S_IDLE;
                end

                default: state_r <= S_IDLE;
            endcase
        end
    end

    // SLRD# konczy sie razem z zamawianiem, ale SLOE# MUSI zostac aktywne, az
    // ostatnie zamowione slowo zejdzie z magistrali (bez zmian wzgledem Gowin).
    assign SLRD_N = ~rd_active_r;
    assign SLOE_N = ~(rd_active_r || (state_r == S_DRAIN));

    assign data_o  = dq_r;
    assign valid_o = vld_r;

endmodule
