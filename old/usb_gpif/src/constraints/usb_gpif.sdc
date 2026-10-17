// Zegar rdzenia = zrodlo PCLK podawanego do FX3. Jedna domena, brak CDC.
create_clock -name clk -period 10.000 [get_ports {clk}]

// UWAGA (doswiadczenie z ../IRIS/top_module/src/constraints/top_module.sdc):
// - set_clock_groups -asynchronous jest ODRZUCANE przez Gowin V1.9.9 (zegary
//   z PLL nie istnieja na etapie parsowania constraintow)
// - set_false_path jest przyjmowane, ale FIZYCZNIE USUWA sciezke sygnalu
//   (zweryfikowane porownaniem bitstreamow)
// Dlatego zadnych constraintow rozdzielajacych domeny - rozdzielenie musi byc
// strukturalne (rejestry, FIFO), nie deklaratywne.
