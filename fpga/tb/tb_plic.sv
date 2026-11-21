// SPDX-License-Identifier: Apache-2.0
// legend_plic: random register traffic and source lines against a behavioural model whose claim
// is the plain definition (the highest priority pending and enabled source, the lowest number
// among equals). Checks every read and both interrupt lines.
`timescale 1ns / 1ps
module tb;
  localparam int NSRC = 31;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic sel = 0, we = 0;
  logic [25:0] addr = '0;
  logic [31:0] wdata = '0, rdata;
  logic [NSRC:1] src = '0;
  logic irq_m, irq_s;
  legend_plic #(.NSRC(NSRC)) dut (.*);

  // the model
  logic [2:0]    m_prio [NSRC+1];
  logic [NSRC:0] m_pend = '0, m_insvc = '0, m_en [2];
  logic [2:0]    m_thr [2];
  logic [31:0]   m_rdata = '0;
  logic          m_irq [2];
  function automatic int best(input int c);
    int b = 0; logic [2:0] bp = 0;
    for (int i = 1; i <= NSRC; i++) if (m_pend[i] && m_en[c][i] && m_prio[i] > bp) begin b = i; bp = m_prio[i]; end
    return b;
  endfunction
  function automatic logic [2:0] bestp(input int c);
    return best(c) == 0 ? 3'd0 : m_prio[best(c)];
  endfunction

  int n = 0, bad = 0, claims = 0, seed = 1;
  logic [25:0] addrs [8] = '{26'h1000, 26'h2000, 26'h2080, 26'h200000, 26'h201000, 26'h200004, 26'h201004, 26'h0};
  logic chk = 0;
  initial begin
    void'($value$plusargs("seed=%d", seed)); void'($urandom(seed));
    for (int i = 0; i <= NSRC; i++) m_prio[i] = 0;
    m_en[0] = '0; m_en[1] = '0; m_thr[0] = 0; m_thr[1] = 0; m_irq[0] = 0; m_irq[1] = 0;
    repeat (3) @(posedge clk);
    rst <= 0;
    repeat (400000) begin
      @(negedge clk);
      // compare what the last edge produced
      if (chk && rdata !== m_rdata) begin bad++; if (bad < 10) $display("rdata %h, model %h, addr %h at %0d", rdata, m_rdata, addr, n); end
      if (irq_m !== m_irq[0] || irq_s !== m_irq[1]) begin bad++; if (bad < 10) $display("irq %b%b, model %b%b at %0d", irq_m, irq_s, m_irq[0], m_irq[1], n); end
      n++;
      // next stimulus
      sel = $urandom_range(3) == 0; we = $urandom_range(1);
      addr = $urandom_range(3) == 0 ? 26'($urandom_range(31) * 4) : addrs[$urandom_range(7)];
      wdata = $urandom_range(3) == 0 ? $urandom_range(40) : $urandom;
      if ($urandom_range(7) == 0) src = $urandom & $urandom;
      else if ($urandom_range(15) == 0) src = '0;
      // the model takes the same edge
      chk = sel && !we;
      m_irq[0] = bestp(0) > m_thr[0]; m_irq[1] = bestp(1) > m_thr[1];
      begin
        logic [NSRC:0] np; int b0, b1;
        np = m_pend; b0 = best(0); b1 = best(1);
        for (int i = 1; i <= NSRC; i++) if (src[i] && !m_insvc[i]) np[i] = 1'b1;
        if (sel && !we && addr == 26'h200004 && b0 != 0) begin np[b0] = 1'b0; m_insvc[b0] = 1'b1; claims++; end
        if (sel && !we && addr == 26'h201004 && b1 != 0) begin np[b1] = 1'b0; m_insvc[b1] = 1'b1; claims++; end
        if (sel && !we) begin
          m_rdata = '0;
          if (addr < 26'h80)           m_rdata = 32'(m_prio[addr[6:2]]);
          else if (addr == 26'h1000)   m_rdata = 32'(m_pend);
          else if (addr == 26'h2000)   m_rdata = 32'(m_en[0]);
          else if (addr == 26'h2080)   m_rdata = 32'(m_en[1]);
          else if (addr == 26'h200000) m_rdata = 32'(m_thr[0]);
          else if (addr == 26'h201000) m_rdata = 32'(m_thr[1]);
          else if (addr == 26'h200004) m_rdata = 32'(b0);
          else if (addr == 26'h201004) m_rdata = 32'(b1);
        end
        if (sel && we) begin
          if (addr < 26'h80 && addr[6:2] != 0) m_prio[addr[6:2]] = wdata[2:0];
          else if (addr == 26'h2000)   m_en[0] = {wdata[NSRC:1], 1'b0};
          else if (addr == 26'h2080)   m_en[1] = {wdata[NSRC:1], 1'b0};
          else if (addr == 26'h200000) m_thr[0] = wdata[2:0];
          else if (addr == 26'h201000) m_thr[1] = wdata[2:0];
          else if ((addr == 26'h200004 || addr == 26'h201004) && wdata[5:0] != 0 && wdata[5:0] <= 6'(NSRC)) m_insvc[wdata[5:0]] = 1'b0;
        end
        m_pend = np;
      end
    end
    $display("@@ plic cycles=%0d claims=%0d mismatches=%0d", n, claims, bad);
    $finish;
  end
endmodule
