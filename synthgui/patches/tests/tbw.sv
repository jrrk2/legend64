module tb;
  logic [63:0] buf_data; logic [2:0] buf_cnt; logic [31:0] arr_word; logic arr_valid, pend_skip;
  wire [63:0] a, b; wire [2:0] ca, cb;
  win     u_ref (.buf_data, .buf_cnt, .arr_word, .arr_valid, .pend_skip, .win_data(a), .win_cnt(ca));
  win_map u_map (.buf_data, .buf_cnt, .arr_word, .arr_valid, .pend_skip, .win_data(b), .win_cnt(cb));
  int bad = 0;
  initial begin
    for (int i = 0; i < 20000; i++) begin
      buf_data = {$urandom, $urandom}; arr_word = $urandom; buf_cnt = 3'(i % 3); arr_valid = i[4]; pend_skip = i[5];
      if (i % 7 == 0) buf_cnt = 3'd3;
      #1;
      if (a !== b || ca !== cb) begin
        bad++;
        if (bad <= 8) $display("cnt %0d valid %b skip %b: buf %h arr %h -> RTL %h netlist %h xor %h", buf_cnt, arr_valid, pend_skip, buf_data, arr_word, a, b, a ^ b);
      end
    end
    $display("%0d of 20000 differ", bad); $finish;
  end
endmodule
