`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// hello_top - modul testowy bring-upu toolchainu Vivado 2017.4 / XC7K325T.
//
// Cel: przepuscic przez CALY przeplyw (symulacja -> synteza -> implementacja
// -> bitstream) kod uzywajacy tych samych konstrukcji SystemVerilog co
// docelowy old/usb_gpif/, zanim zainwestujemy w port tamtego modulu.
//
// Funkcjonalnie: dzielnik zegara miga LED, licznik 4-bitowy wystawiony na
// LED, automat 3-stanowy steruje licznikiem. Nic z tego nie jest potrzebne
// w projekcie - to atrapa obciazenia dla narzedzi.
//
// PORTY: malo i celowo - kazdy port wymaga PACKAGE_PIN i IOSTANDARD w .xdc,
// inaczej write_bitstream odmawia (patrz naglowek bft_full_kintex7.xdc w
// examples/). Pinout FFG676 nie jest jeszcze ustalony, wiec .xdc to atrapa.
//
// KONWENCJE (z ../IRIS/CLAUDE.md, zachowane):
//   - komentarze po polsku, ASCII bez diakrytykow
//   - UPPER_CASE dla pinow fizycznych, _i/_o dla portow wewnetrznych
//   - reset SYNCHRONICZNY, aktywny wysoko, if (reset) wewnatrz always_ff
//   - sufiks _r dla rejestrow, prefiks u_ dla instancji
////////////////////////////////////////////////////////////////////////////////
module hello_top
    import hello_pkg::*;
(
    input  wire                    CLK,        // zegar systemowy
    input  wire                    RESET,      // synchroniczny, aktywny wysoko
    output wire                    LED_HEART,  // migotanie ~1 Hz - "zyje"
    output wire [COUNT_WIDTH-1:0]  LED_COUNT   // licznik testowy
);

    // ------------------------------------------------------------------------
    // Dzielnik zegara. Licznik szerokosci wyliczonej w pakiecie ($clog2),
    // nie wpisanej recznie - to celowy test wnioskowania szerokosci.
    // ------------------------------------------------------------------------
    logic [BLINK_CNT_W-1:0] div_cnt_r;
    logic                   heart_r;

    always_ff @(posedge CLK) begin
        if (RESET) begin
            div_cnt_r <= '0;
            heart_r   <= 1'b0;
        end else if (div_cnt_r == BLINK_DIV[BLINK_CNT_W-1:0] - 1) begin
            div_cnt_r <= '0;
            heart_r   <= ~heart_r;      // przelot licznika -> zmiana stanu LED
        end else begin
            div_cnt_r <= div_cnt_r + 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // Automat - odpowiednik struktury z usb_gpif_rx.sv. Sens jest wylacznie
    // testowy: sprawdza typ wyliczeniowy z pakietu, case po nim i przejscia.
    //
    // S_IDLE -> S_RUN  : po zwolnieniu resetu
    // S_RUN  -> S_HOLD : gdy licznik dojdzie do konca zakresu
    // S_HOLD -> S_RUN  : przy nastepnym przelocie dzielnika
    // ------------------------------------------------------------------------
    hello_state_t           state_r;
    logic [COUNT_WIDTH-1:0] count_r;

    // Przelot dzielnika - jeden takt na "tyknieciu" licznika sekundowego.
    wire tick = (div_cnt_r == '0) && !RESET;

    always_ff @(posedge CLK) begin
        if (RESET) begin
            state_r <= S_IDLE;
            count_r <= '0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    state_r <= S_RUN;
                end

                S_RUN: begin
                    if (tick) begin
                        count_r <= count_r + 1'b1;
                        if (count_r == {COUNT_WIDTH{1'b1}}) state_r <= S_HOLD;
                    end
                end

                S_HOLD: begin
                    if (tick) state_r <= S_RUN;
                end

                default: state_r <= S_IDLE;
            endcase
        end
    end

    assign LED_HEART = heart_r;
    assign LED_COUNT = count_r;

endmodule
