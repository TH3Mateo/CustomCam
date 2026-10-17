`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif_dev_tb - test wariantu bring-up.
//
// Reuzywa modelu FX3 z usb_gpif_tb (te same tCO/tCFLG, te same przerwy miedzy
// buforami DMA), ale sprawdza wyjscia diagnostyczne zamiast strumienia:
//   led_error     - musi zostac 0 przez caly transfer
//   led_stream_ok - musi zaczac migac (checker zlicza poprawne slowa)
////////////////////////////////////////////////////////////////////////////////
import usb_gpif_pkg::*;

module usb_gpif_tb;

    localparam int unsigned N_WORDS   = 4096;
    localparam int unsigned DMA_BUF_W = 256;
    localparam TCO   = 7;
    localparam TCFLG = 8;

    logic clk = 1'b0;
    logic reset = 1'b1;
    always #5 clk = ~clk;

    wire [31:0] DQ;
    wire        SLRD_N, SLOE_N;
    logic       FLAG_EMPTY;
    wire        led_stream_ok, led_error;

    int errors = 0;

    usb_gpif_dev dut (
        .clk          (clk),
        .reset        (reset),
        .DQ           (DQ),
        .FLAG_EMPTY   (FLAG_EMPTY),
        .SLRD_N       (SLRD_N),
        .SLOE_N       (SLOE_N),
        .led_stream_ok(led_stream_ok),
        .led_error    (led_error)
    );

    // --- Model FX3 (identyczny jak w usb_gpif_tb) ---
    logic [31:0] fx3_dq_r = 32'hxxxx_xxxx;
    logic [31:0] fx3_next_word = 32'h0;
    logic [31:0] fx3_words_sent = 0;
    logic signed [31:0] fx3_buf_left = DMA_BUF_W;
    logic        fx3_has_data = 1'b0;

    localparam int FLAG_LEAD = RD_LATENCY + 2;

    // Po wyczerpaniu strumienia FX3 nie ma juz czego wystawiac - magistrala
    // wraca w stan wysokiej impedancji. Bez tego model trzymalby ostatnie slowo,
    // ktore RX slusznie odebralby powtornie w S_DRAIN (blad na koncu testu,
    // nie w RTL).
    assign DQ = (!SLOE_N && fx3_words_sent < N_WORDS) ? fx3_dq_r : 32'hzzzz_zzzz;

    // FX3 wystawia dane po tCO=7ns od zbocza, ktore zobaczylo aktywne SLRD#
    // (tCO < okres 10ns, wiec jeszcze w tym samym okresie). Dane pozostaja na
    // magistrali dopoki SLOE# jest aktywne - wskaznik FIFO w FX3 przesuwa sie
    // dokladnie raz na aktywny SLRD#, slowa nie gina "w powietrzu".
    // Wskaznik FX3 przesuwa sie na KAZDYM zboczu z aktywnym SLRD#; dane laduja
    // na magistrali tCO=7ns pozniej. Decyzja i opoznienie MUSZA byc rozdzielone:
    // `#(TCO)` wewnatrz always sekwencyjnie blokuje blok i przesuwa cala reakcje
    // modelu o cykl (widoczne w sladzie jako "FX3 wystawia ... SLRDn=1").
    logic [31:0] fx3_pending;
    logic        fx3_emit = 1'b0;

    always @(posedge clk) begin
        fx3_emit <= 1'b0;
        if (!SLRD_N && fx3_words_sent < N_WORDS) begin
            fx3_pending    <= fx3_next_word;
            fx3_emit       <= 1'b1;
            fx3_next_word  <= fx3_next_word + 1;
            fx3_words_sent <= fx3_words_sent + 1;
            fx3_buf_left   <= fx3_buf_left - 1;
        end
    end

    always @(posedge fx3_emit) #(TCO) fx3_dq_r = fx3_pending;

    always @(posedge clk) begin
        #(TCFLG);
        if (fx3_words_sent >= N_WORDS)      FLAG_EMPTY <= 1'b0;
        else if (fx3_buf_left <= FLAG_LEAD) FLAG_EMPTY <= 1'b0;
        else                                FLAG_EMPTY <= fx3_has_data;
    end

    initial begin
        FLAG_EMPTY   = 1'b0;
        fx3_has_data = 1'b0;
        @(negedge reset);
        repeat (5) @(posedge clk);
        forever begin
            fx3_buf_left <= DMA_BUF_W;
            fx3_has_data = 1'b1;
            wait (fx3_buf_left <= FLAG_LEAD || fx3_words_sent >= N_WORDS);
            wait (SLRD_N === 1'b1 || fx3_words_sent >= N_WORDS);
            fx3_has_data = 1'b0;
            if (fx3_words_sent >= N_WORDS) break;
            repeat (6) @(posedge clk);
        end
    end

    // led_error musi pozostac 0 przez caly czas
    always @(posedge clk) begin
        if (!reset && led_error) begin
            if (errors == 0) $display("BLAD @%0t: led_error podniesione", $time);
            errors = errors + 1;
        end
    end

    initial begin
        $dumpfile("outputs/sim/usb_gpif_tb.vcd");
        $dumpvars(0, usb_gpif_tb);

        repeat (10) @(posedge clk);
        reset <= 1'b0;

        wait (fx3_words_sent >= N_WORDS);
        repeat (100) @(posedge clk);

        $display("");
        $display("Przeslano slow przez FX3 : %0d", fx3_words_sent);
        $display("Slow zaliczonych przez checker: %0d", dut.ok_cnt_r);
        $display("led_error                : %b", led_error);

        if (dut.ok_cnt_r < N_WORDS - 2) begin
            $display("BLAD: checker zaliczyl tylko %0d slow", dut.ok_cnt_r);
            errors = errors + 1;
        end

        if (errors == 0) $display("\n=== PASS: wszystkie testy zaliczone ===");
        else             $display("\n=== FAIL: %0d bledow ===", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("\n=== FAIL: timeout ===");
        $finish;
    end

endmodule
