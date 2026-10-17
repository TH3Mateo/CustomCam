////////////////////////////////////////////////////////////////////////////////
// usb_gpif_fifo - bufor elastycznosci miedzy odbiornikiem GPIF II a odbiorca
//                 (docelowo dekoder MJPEG).
//
// FIFO SYNCHRONICZNE - jedna domena zegara. Bylo mozliwe dopiero dzieki decyzji
// "PCLK generuje FPGA": gdyby zegar dawal FX3, trzeba by tu FIFO asynchroniczne
// ze wskaznikami Graya i synchronizatorami. Patrz naglowek usb_gpif_rx.sv.
//
// Rola bufora: FX3 dostarcza dane paczkami (bufory DMA), a odbiorca moze
// chwilowo zwalniac. FIFO wyrownuje te nierownomiernosci i - przez almost_full_o
// - z wyprzedzeniem hamuje odczyt z FX3, zanim zabraknie miejsca.
//
// Pamiec jest wnioskowana (blokowa, styl "RAM z rejestrem adresu odczytu"),
// nie instancjonowana jawnie jako SDPB. Przy 512 x 32 bity synteza Gowin
// powinna uzyc 1 BSRAM - do potwierdzenia w raporcie zasobow po syntezie.
////////////////////////////////////////////////////////////////////////////////
module usb_gpif_fifo
    import usb_gpif_pkg::*;
#(
    parameter int unsigned DEPTH      = FIFO_DEPTH,
    parameter int unsigned ADDR_BITS  = FIFO_ADDR_BITS,
    parameter int unsigned AF_MARGIN  = ALMOST_FULL_MARGIN
) (
    input  logic                  clk,
    input  logic                  rst,

    // --- Wejscie (od usb_gpif_rx) ---
    input  logic [DATA_WIDTH-1:0] wr_data_i,
    input  logic                  wr_valid_i,
    output logic                  almost_full_o,

    // --- Wyjscie (do odbiorcy) ---
    output logic [DATA_WIDTH-1:0] rd_data_o,
    output logic                  rd_valid_o,
    input  logic                  rd_ready_i,

    // --- Diagnostyka ---
    output logic [ADDR_BITS:0]    level_o,
    output logic                  overflow_o
);

    logic [DATA_WIDTH-1:0] mem_r [DEPTH-1:0];

    // Wskazniki maja bit dodatkowy - rozroznia stan pusty od pelnego przy
    // rownych adresach.
    logic [ADDR_BITS:0] wr_ptr_r, rd_ptr_r;

    wire [ADDR_BITS-1:0] wr_addr = wr_ptr_r[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr = rd_ptr_r[ADDR_BITS-1:0];

    wire empty = (wr_ptr_r == rd_ptr_r);
    wire full  = (wr_ptr_r[ADDR_BITS-1:0] == rd_ptr_r[ADDR_BITS-1:0]) &&
                 (wr_ptr_r[ADDR_BITS]     != rd_ptr_r[ADDR_BITS]);

    assign level_o = wr_ptr_r - rd_ptr_r;

    // Hamowanie z wyprzedzeniem: odczyt z FX3 jest w locie przez RD_LATENCY
    // cykli po zdjeciu SLRD#, wiec margines musi pokryc slowa, ktore i tak
    // jeszcze naplyna. Inaczej FIFO sie przepelni mimo poprawnej logiki.
    assign almost_full_o = (level_o >= (DEPTH - AF_MARGIN));

    wire do_wr = wr_valid_i && !full;
    wire do_rd = rd_valid_r && rd_ready_i;   // tylko do statystyk/level

    // ------------------------------------------------------------------------
    // Zapis
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (do_wr) mem_r[wr_addr] <= wr_data_i;
    end

    always_ff @(posedge clk) begin
        if (rst) wr_ptr_r <= '0;
        else if (do_wr) wr_ptr_r <= wr_ptr_r + 1'b1;
    end

    // Utrata slowa przy pelnym FIFO. Nie powinno wystapic - almost_full_o ma
    // temu zapobiec - ale jesli wystapi, strumien MJPEG jest juz uszkodzony,
    // wiec musi to byc widoczne, a nie ciche.
    always_ff @(posedge clk) begin
        if (rst) overflow_o <= 1'b0;
        else if (wr_valid_i && full) overflow_o <= 1'b1;
    end

    // ------------------------------------------------------------------------
    // Odczyt. Wyjscie rejestrowane (1 cykl opoznienia za wskaznikiem), zeby
    // synteza mogla uzyc BSRAM z rejestrem wyjsciowym zamiast rozproszonej LUT.
    // ------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] rd_data_r;
    logic                  rd_valid_r;

    // Rejestr wyjsciowy wolno zaladowac TYLKO gdy jest pusty albo gdy odbiorca
    // wlasnie zabral slowo. Bezwarunkowa aktualizacja co cykl podmienialaby
    // dane pod trzymanym valid_o - zlamanie kontraktu valid/ready i zgubione
    // slowa (wykryte w symulacji: slowa dublowaly sie przy ready_i=0).
    wire load_out = !empty && (!rd_valid_r || rd_ready_i);

    // Read-during-write: gdy odbiorca nadaza na biezaco (ready stale wysokie),
    // slowo bywa czytane w TYM SAMYM cyklu, w ktorym jest wpisywane. Pamiec
    // zwrocilaby wtedy stara zawartosc komorki, wiec dane trzeba podac obok
    // niej. Bez tego gubi sie po 1 slowie na kazda granice bufora DMA - moment,
    // w ktorym FIFO chwilowo pustoszeje (wykryte testem wariantu _dev, gdzie
    // ready_i=1 na stale; test rdzenia z losowym backpressure tego nie lapal).
    wire rdw_bypass = do_wr && (wr_addr == rd_addr);

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr_r   <= '0;
            rd_valid_r <= 1'b0;
            rd_data_r  <= '0;
        end else begin
            // Rejestr zwalnia sie, gdy odbiorca zabral slowo. Dopiero wtedy
            // (albo gdy jest pusty) wolno zaladowac kolejne.
            if (do_rd) rd_valid_r <= 1'b0;

            if (load_out) begin
                rd_data_r  <= rdw_bypass ? wr_data_i : mem_r[rd_addr];
                rd_valid_r <= 1'b1;
                rd_ptr_r   <= rd_ptr_r + 1'b1;
            end
        end
    end

    assign rd_data_o  = rd_data_r;
    assign rd_valid_o = rd_valid_r;

endmodule
