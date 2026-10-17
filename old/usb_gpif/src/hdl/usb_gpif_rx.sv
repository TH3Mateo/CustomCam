////////////////////////////////////////////////////////////////////////////////
// usb_gpif_rx - odbiornik strumienia z FX3 (CYUSB3014) przez GPIF II
//               w trybie Synchronous Slave FIFO, FPGA jako master.
//
// Tor jest WYLACZNIE odbiorczy (FX3 -> FPGA). Nie ma zapisu, wiec nie ma
// SLWR#/PKTEND#; SLCS# jest zwarty do GND na PCB, A[1:0] na stale 0.
// Patrz .claude/PINOUT.md - redukcja 44 -> 35 pinow.
//
// --- DLACZEGO PROBKOWANIE ZBOCZEM OPADAJACYM (nie zmieniac bez pomiarow!) ---
// FX3 ma tCO = 7 ns max (CYUSB3014.pdf Tab. 13/15) przy okresie PCLK 10 ns.
// PCLK generuje FPGA, wiec budzet jest typu round-trip:
//     10 ns - tPD(clk FPGA->FX3) - tCO(7) - tPD(dane FX3->FPGA) - tSU
//   = 10 - 1 - 7 - 1 - 1 = 0 ns  --> zbocze narastajace NIE DZIALA.
// Zbocze opadajace dokłada pol okresu (5 ns), co daje ~5 ns marginesu.
// Dlatego dane sa rejestrowane na NEGEDGE PCLK. To wyglada na blad przy
// pobieznym czytaniu i kusi, zeby "naprawic" na posedge - NIE ROBIC TEGO.
// Wariant zapasowy gdyby 5 ns okazalo sie za malo na sprzecie: IODELAY na DQ.
//
// --- BRAK CDC ---
// PCLK pochodzi z tego samego PLL co clk (domena rdzenia), wiec caly modul
// pracuje w jednej domenie i nie ma tu synchronizatorow ani async FIFO.
// To byl glowny powod wyboru "PCLK z FPGA" zamiast "PCLK od FX3".
////////////////////////////////////////////////////////////////////////////////
module usb_gpif_rx
    import usb_gpif_pkg::*;
(
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

    // Zamowienie slowa. Zanim odpowiadajace mu dane wroca na DQ, mija:
    //   +1 cykl - FX3 przetwarza SLRD# i wystawia dane po tCO (Tab. 15)
    // Dopiero tak opozniony znacznik wchodzi do rejestru wejsciowego RAZEM
    // z danymi, wiec dalej nie moga sie juz rozjechac.
    logic req_r;         // zamowienie zlozone (SLRD# aktywne)
    logic word_taken;    // dane tego zamowienia sa wlasnie na DQ

    // Zamowienie = dokladnie to, co widzi FX3 na pinie SLRD#. Potok ponizej
    // biegnie dalej takze w S_DRAIN - slowa zamowione w ostatnich cyklach
    // S_READ musza dostac znacznik waznosci juz po zdjeciu SLRD#, bo dane
    // docieraja do dq_r dopiero 2 cykle pozniej (magistrala jest wtedy nadal
    // napedzana, bo SLOE# trwa dluzej - patrz nizej).
    assign req_r = rd_active_r;

    // Droga danych od zamowienia do dq_r:
    //   SLRD# aktywne -> FX3 wystawia dane po tCO=7ns (jeszcze w tym okresie,
    //   bo tCO < 10ns) -> rejestr negedge (+1) -> rejestr posedge (+1).
    // Znacznik musi przejsc TE SAME 2 stopnie. Wczesniej bylo 3 - znacznik
    // wlokl sie cykl za danymi, przez co ostatnie slowo kazdego bufora DMA
    // nie dostawalo waznosci i przepadalo (1 slowo na granice).
    logic req_d1_r, req_d2_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            req_d1_r <= 1'b0;
            req_d2_r <= 1'b0;
        end else begin
            req_d1_r <= req_r;
            req_d2_r <= req_d1_r;
        end
    end

    assign word_taken = req_d2_r;

    // ------------------------------------------------------------------------
    // Rejestr wejsciowy na ZBOCZU OPADAJACYM - patrz naglowek pliku.
    // ------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] dq_neg_r;

    // Razem z danymi wedruje znacznik waznosci - ta sama droga, ten sam
    // rejestr, wiec z definicji nie moga sie rozjechac. Wczesniejsza wersja
    // liczyla cykle osobnym potokiem od rd_active_r i 'valid' wyprzedzal dane
    // o 2 cykle (widoczne w sondzie jako valid=1 nad danymi 'xxxxxxxx').
    always_ff @(negedge clk) begin
        dq_neg_r <= DQ;
    end

    // Przepisanie do domeny posedge. dq_neg_r jest stabilne od polowy okresu,
    // wiec ma pelne pol okresu setupu do nastepnego zbocza narastajacego.
    logic [DATA_WIDTH-1:0] dq_r;
    logic                  vld_r;

    // Znacznik waznosci idzie WYLACZNIE przez posedge, rownolegle do drogi
    // danych. Przepuszczenie go przez rejestr negedge (jak dane) przesuwaloby
    // go o pol cyklu w druga strone niz dane i nie dalo sie zgrac zadna stala.

    always_ff @(posedge clk) begin
        dq_r  <= dq_neg_r;
        vld_r <= rst ? 1'b0 : word_taken;
    end

    // ------------------------------------------------------------------------
    // Automat. Warunek czytania: FX3 ma dane ORAZ jest gdzie je odlozyc.
    // ------------------------------------------------------------------------
    logic can_read;
    assign can_read = FLAG_EMPTY && !almost_full_i;

    // Po zdjeciu SLRD# slowa zamowione wczesniej sa jeszcze w drodze (FX3 +
    // rejestry wejsciowe). Zamiast liczyc je pojedynczo, odczekujemy stala
    // liczbe cykli - droga jest z gory znana i niezmienna (RD_LATENCY).
    // Wczesniejsza wersja z licznikiem inkrementowanym na zamowieniu, a
    // dekrementowanym na waznosci, wchodzila w stan X (rozjezdzajace sie
    // domeny posedge/negedge) i automat wisial w S_DRAIN na zawsze.
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
                // rd_active_r sledzi can_read cykl po cyklu - nie jest trzymane
                // na sztywno przez caly stan. Dzieki temu opadniecie FLAG od razu
                // wstrzymuje zamawianie i nie powstaja slowa-widma (cykle SLRD#
                // aktywne bez danych po stronie FX3).
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
    // ostatnie zamowione slowo zejdzie z magistrali. Zdjecie obu naraz zwalnia
    // DQ w chwili, gdy slowa zamowione wczesniej sa jeszcze w drodze - trafiaja
    // wtedy na magistrale juz w stanie wysokiej impedancji (w symulacji: po 2
    // slowa 'zzzzzzzz' na kazda granice bufora DMA).
    //
    // Na PCB oba piny sa zwarte dla oszczednosci 1 pinu (patrz .claude/PINOUT.md)
    // - przy zwarciu obowiazuje przebieg SLOE#, czyli ten dluzszy. Jest to
    // bezpieczne: dodatkowe cykle SLOE# bez SLRD# tylko trzymaja dane na
    // magistrali, nie inkrementuja wskaznika FIFO w FX3.
    assign SLRD_N = ~rd_active_r;
    assign SLOE_N = ~(rd_active_r || (state_r == S_DRAIN));

    assign data_o  = dq_r;
    assign valid_o = vld_r;

endmodule
