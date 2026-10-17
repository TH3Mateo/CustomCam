`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// usb_gpif_dev_tb - test wariantu bring-up na Kintex-7.
//
// Port testbencha Gowin (old/usb_gpif/src/tb/usb_gpif_tb.sv) - model FX3
// BEZ ZMIAN (tCO=7ns, tCFLG=8ns, przerwy miedzy buforami DMA sa wlasnoscia
// FX3, nie zaleza od tego, jak FPGA probkuje DQ). Zmiany dotycza wylacznie
// obudowania: dochodzi idelay_refclk i oczekiwanie na kalibracje IDELAYCTRL
// przed zwolnieniem resetu - bez tego pierwsze probkowania DQ trafilyby na
// niekalibrowane IDELAYE2.
//
// Banner PASS/FAIL zgodny z konwencja toolchainu (patrz Makefile/hello_tb.sv) -
// Makefile grepuje "=== PASS" po logu, bo xsim nie daje wiarygodnego kodu
// wyjscia (patrz .claude/WYNIKI_toolchain.md, "$fatal daje exit 0").
////////////////////////////////////////////////////////////////////////////////
import usb_gpif_pkg::*;

module usb_gpif_dev_tb;

    localparam int unsigned N_WORDS   = 4096;
    localparam int unsigned DMA_BUF_W = 256;
    localparam TCO   = 7;
    localparam TCFLG = 8;

    logic clk = 1'b0;
    always #5 clk = ~clk;              // 100 MHz - PCLK/domena rdzenia

    // IDELAYCTRL wymaga wlasnego zegara referencyjnego, niezaleznego od
    // domeny PCLK (patrz naglowek usb_gpif_dev.sv - do zweryfikowania
    // czestotliwosci w UG471 przed synteza na sprzecie; tu 200 MHz jako
    // wartosc robocza do symulacji funkcjonalnej).
    logic idelay_refclk = 1'b0;
    always #2.5 idelay_refclk = ~idelay_refclk;   // 200 MHz

    logic reset = 1'b1;

    wire [31:0] DQ;
    wire        SLRD_N, SLOE_N;
    logic       FLAG_EMPTY;
    wire        led_stream_ok, led_error;

    int errors = 0;

    usb_gpif_dev dut (
        .clk          (clk),
        .idelay_refclk(idelay_refclk),
        .reset        (reset),
        .DQ           (DQ),
        .FLAG_EMPTY   (FLAG_EMPTY),
        .SLRD_N       (SLRD_N),
        .SLOE_N       (SLOE_N),
        .led_stream_ok(led_stream_ok),
        .led_error    (led_error)
    );

    // --- Model FX3 (identyczny jak w wersji Gowin - nie zalezy od IDELAY) ---
    logic [31:0] fx3_dq_r = 32'hxxxx_xxxx;
    logic [31:0] fx3_next_word = 32'h0;
    logic [31:0] fx3_words_sent = 0;
    logic signed [31:0] fx3_buf_left = DMA_BUF_W;
    logic        fx3_has_data = 1'b0;

    localparam int FLAG_LEAD = RD_LATENCY + 2;

    // Po wyczerpaniu strumienia FX3 nie ma juz czego wystawiac - magistrala
    // wraca w stan wysokiej impedancji. Bez tego model trzymalby ostatnie
    // slowo, ktore RX slusznie odebralby powtornie w S_DRAIN.
    assign DQ = (!SLOE_N && fx3_words_sent < N_WORDS) ? fx3_dq_r : 32'hzzzz_zzzz;

    // FX3 wystawia dane po tCO=7ns od zbocza z aktywnym SLRD# (tCO < okres
    // 10ns, wiec jeszcze w tym samym okresie). Decyzja i opoznienie MUSZA byc
    // rozdzielone - #(TCO) wewnatrz always sekwencyjnie przesuwaloby cala
    // reakcje modelu o cykl.
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
        $display("=====================================================");
        $display(" usb_gpif_dev_tb - port na Kintex-7 (IDELAYE2 zamiast negedge)");
        $display("=====================================================");

        // Zewnetrzny reset (POR/przycisk) zwalniany PO KROTKIM czasie, tak jak
        // na sprzecie - nie czekamy tu na IDELAYCTRL.RDY, bo to wlasnie
        // IDELAYCTRL.RST=reset MUSI zejsc, zeby kalibracja w ogole ruszyla
        // (RST=1 trzyma model w stanie "lost", RDY nigdy by sie nie podnioslo -
        // pierwsza wersja tego testbencha miala tu zapetlenie: czekala na RDY
        // przed zwolnieniem sygnalu, ktory sam blokuje RDY).
        //
        // Ochrone przed niekalibrowanym IDELAYE2 daje reset_sync WEWNATRZ
        // usb_gpif_dev (reset || !idelayctrl_rdy) - to jego zadanie, nie
        // testbencha. Tu czekamy tylko na RDY, zeby wiedziec, kiedy rdzen
        // faktycznie wyjdzie z resetu wewnetrznego.
        repeat (10) @(posedge clk);
        reset <= 1'b0;
        wait (dut.idelayctrl_rdy);
        $display("INFO: IDELAYCTRL RDY @%0t", $time);
        repeat (5) @(posedge clk);

        wait (fx3_words_sent >= N_WORDS);
        repeat (100) @(posedge clk);

        $display("");
        $display("Przeslano slow przez FX3       : %0d", fx3_words_sent);
        $display("Slow zaliczonych przez checker  : %0d", dut.ok_cnt_r);
        $display("led_error                      : %b", led_error);

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
