// SPDX-License-Identifier: Apache-2.0
// Unit testbench for legend64_fpu: replays reference vectors (scripts/fpu_vectors.c) and compares
// the result and exception flags of every operation.
`timescale 1ns / 1ps
module tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic        start = 0, busy, done;
  logic [31:0] insn;
  logic [63:0] a, b, c, x, result, exp_res;
  logic [2:0]  rm;
  logic [4:0]  flags;
  logic [7:0]  exp_fl;
  legend64_fpu dut (.clk, .rst_n, .start, .accept(done), .insn, .a_raw(a), .b_raw(b), .c_raw(c), .x_in(x), .rm,
                   .busy, .done, .result, .flags);
  int fd, n = 0, bad = 0, rmi;
  string vec;
  initial begin
    if (!$value$plusargs("vec=%s", vec)) $fatal(1, "need +vec=<file>");
    fd = $fopen(vec, "r");
    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    while ($fscanf(fd, "%h %h %h %h %h %d %h %h", insn, a, b, c, x, rmi, exp_res, exp_fl) == 8) begin
      rm = 3'(rmi);
      start = 1;
      #1;
      while (!done) begin @(posedge clk); #1; end
      n++;
      if (result !== exp_res || flags !== exp_fl[4:0]) begin
        bad++;
        if (bad <= 15) $display("MISMATCH insn=%08x rm=%0d a=%016x b=%016x c=%016x x=%016x got=%016x/%02x exp=%016x/%02x",
                                insn, rm, a, b, c, x, result, flags, exp_res, exp_fl);
      end
      @(posedge clk);
      start = 0;
      #1;
    end
    $display("@@ fpu vectors=%0d mismatches=%0d", n, bad);
    $finish;
  end
endmodule
