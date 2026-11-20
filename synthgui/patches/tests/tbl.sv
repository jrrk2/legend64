module tb;
  logic clk = 0, we = 0; logic [5:0] wa = 0, ra = 0; logic [1:0] wd = 0; logic [4:0] ra2 = 0;
  wire [1:0] a, b; wire [7:0] a2, b2;
  lram     u_ref (.clk, .we, .wa, .ra, .wd, .rd(a), .ra2, .rd2(a2));
  lram_map u_map (.clk, .we, .wa, .ra, .wd, .rd(b), .ra2, .rd2(b2));
  int bad = 0;
  initial begin
    #1;
    for (int i = 0; i < 64; i++) begin ra = 6'(i); ra2 = 5'(i); #1; if (a !== b || a2 !== b2) begin bad++; if (bad < 4) $display("initial word %0d: %b/%b %h/%h", i, a, b, a2, b2); end end
    for (int i = 0; i < 2000; i++) begin
      we = 1; wa = 6'($urandom); wd = 2'($urandom); ra = 6'($urandom); ra2 = 5'($urandom);
      #1 clk = 1; #1 clk = 0; #1;
      if (a !== b || a2 !== b2) bad++;
    end
    $display("%0d differ", bad); $finish;
  end
endmodule
