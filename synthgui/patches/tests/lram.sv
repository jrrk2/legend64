module lram (input logic clk, input logic we, input logic [5:0] wa, ra, input logic [1:0] wd, output logic [1:0] rd,
             input logic [4:0] ra2, output logic [7:0] rd2);
  logic [1:0] t [64];
  initial for (int i = 0; i < 64; i++) t[i] = 2'b01;
  assign rd = t[ra];
  always_ff @(posedge clk) if (we) t[wa] <= wd;
  // a wider one with a different value per word, never the same in two words
  logic [7:0] u [32];
  initial for (int i = 0; i < 32; i++) u[i] = 8'(i * 7 + 3);
  assign rd2 = u[ra2];
  always_ff @(posedge clk) if (we) u[wa[4:0]] <= {wd, wd, wd, wd};
endmodule
