////////////////////////////////////////////////////////////////////////////////
// hello_tb - testbench modulu testowego toolchainu.
//
// DLACZEGO BANNER PASS/FAIL, A NIE KOD WYJSCIA:
// Zmierzone w instalacji - bin/xvlog.bat i bin/xelab.bat koncza sie na
// "call loader.bat" BEZ "exit /b %errorlevel%" (ktore ma bin/vivado.bat).
// Kod bledu przepada, wiec Makefile oparty na kodzie wyjscia symulacji
// zawsze raportowalby sukces. Dlatego wynik ide przez stdout: testbench
// drukuje jednoznaczny banner, a Makefile go grepuje.
//
// Skrocone czasy: dzielnik 1 Hz przy 100 MHz to 50 mln taktow - symulacja
// trwalaby wieki. TB nie czeka na realne migotanie, tylko sprawdza logike
// na skroconym oknie i weryfikuje to, co da sie sprawdzic szybko.
////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module hello_tb;

    import hello_pkg::*;

    localparam int unsigned CLK_PERIOD_NS = 10;   // 100 MHz
    localparam int unsigned RUN_CYCLES    = 2000; // okno obserwacji

    logic                   clk;
    logic                   reset;
    logic                   led_heart;
    logic [COUNT_WIDTH-1:0] led_count;

    int unsigned errors = 0;

    hello_top u_dut (
        .CLK       (clk),
        .RESET     (reset),
        .LED_HEART (led_heart),
        .LED_COUNT (led_count)
    );

    // Zegar
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    // --- Kontrola ---
    initial begin
        $display("=====================================================");
        $display(" hello_tb - test toolchainu Vivado 2017.4 / XC7K325T");
        $display("=====================================================");

        reset = 1'b1;
        repeat (5) @(posedge clk);

        // Sprawdzenie 1: reset zeruje wyjscia.
        if (led_count !== '0) begin
            $display("BLAD: po resecie led_count=%0d, oczekiwano 0", led_count);
            errors++;
        end
        if (led_heart !== 1'b0) begin
            $display("BLAD: po resecie led_heart=%b, oczekiwano 0", led_heart);
            errors++;
        end

        @(posedge clk);
        reset = 1'b0;
        $display("INFO: reset zwolniony @%0t", $time);

        // Sprawdzenie 2: automat wychodzi z S_IDLE. Siegam do wnetrza DUT -
        // dopuszczalne w TB i sprawdza, czy typ wyliczeniowy z pakietu jest
        // widoczny w hierarchii (test konstrukcji SV, nie funkcji).
        repeat (3) @(posedge clk);
        if (u_dut.state_r == S_IDLE) begin
            $display("BLAD: automat nie wyszedl z S_IDLE po zwolnieniu resetu");
            errors++;
        end else begin
            $display("INFO: automat w stanie %s", u_dut.state_r.name());
        end

        // Sprawdzenie 3: dzielnik liczy (nie stoi).
        begin
            automatic logic [BLINK_CNT_W-1:0] div_start = u_dut.div_cnt_r;
            repeat (RUN_CYCLES) @(posedge clk);
            if (u_dut.div_cnt_r == div_start) begin
                $display("BLAD: dzielnik stoi - div_cnt_r=%0d bez zmian", div_start);
                errors++;
            end else begin
                $display("INFO: dzielnik liczy: %0d -> %0d",
                         div_start, u_dut.div_cnt_r);
            end
        end

        // Sprawdzenie 4: reset dziala takze w trakcie pracy (synchroniczny).
        reset = 1'b1;
        repeat (3) @(posedge clk);
        if (u_dut.div_cnt_r !== '0) begin
            $display("BLAD: reset w trakcie pracy nie wyzerowal dzielnika");
            errors++;
        end else begin
            $display("INFO: reset synchroniczny dziala");
        end

        // --- Podsumowanie ---
        $display("-----------------------------------------------------");
        $display("Bledow: %0d", errors);
        if (errors == 0)
            $display("=== PASS: wszystkie testy zaliczone ===");
        else
            $display("=== FAIL: wykryto %0d bledow ===", errors);
        $display("-----------------------------------------------------");

        $finish;
    end

    // Bezpiecznik - gdyby TB zawisl, ma sie skonczyc FAILem, a nie wisiec.
    initial begin
        #1_000_000;
        $display("=== FAIL: timeout testbencha ===");
        $finish;
    end

endmodule
