// SPDX-License-Identifier: Apache-2.0
// Boots real firmware and a real kernel on the simulated SoC. The DDR3 controller is replaced
// by a behavioural line memory that is preloaded with the images; a small reset stub in the
// boot memory jumps to the firmware. Console output is printed as it appears.
//
//   +load=<file>@<hex address>   (repeatable through +load0= .. +load3=)
//   +until=<text>                stop when this text appears on the console
//   +type=<text>                 once +after= has appeared, send this text (\n as ^) to the UART
//   +max_cycles=<n>              give up after this many clock cycles
//   +progress=<n>                print the program counter and privilege every n cycles
//
// The Ethernet peer checks the IPv4 header checksum and the TCP or UDP checksum of every frame
// the SoC sends, answers ARP, and sends every TCP segment straight back with the addresses and
// ports exchanged. To the SoC's TCP that is a simultaneous open with a peer that says exactly
// what it says itself, so whatever a program writes to such a connection it also reads from it:
// a loop through the transmit and receive offloads.
//   +tcpsink   instead, be a TCP server that accepts any connection, acknowledges what arrives
//              in order and reports anything that arrives out of order: a segment the SoC
//              should have sent and did not shows up here as a gap
//   +sinkdelay=<cycles>   the sink's replies leave that much later (15000 is 0.3 ms, a LAN round
//              trip), so the sender runs ahead of its acknowledgements and sends in bursts
`timescale 1ns / 1ps
module tb;
  logic clk = 0, rst = 1;
  always #10 clk = ~clk;
  logic         mem_req, mem_we, mem_ack = 0;
  logic [23:0]  mem_addr;
  logic [511:0] mem_wdata, mem_rdata;
  logic [7:0]   led;
  logic         uart_tx, uart_rx = 1;
  longint cycles = 0, max_cycles = 64'd4_000_000_000, progress = 0, reads = 0, writes = 0;
  string until_s = "", type_s = "", after_s = "";
  int until_i = 0, after_i = 0;
  bit typing = 0;

  localparam int unsigned SIM_CLK_HZ = 50_000_000;
  localparam int unsigned SIM_BAUD   = 115_200;      // as on the board: transmit timing matters to the driver
  legend64_soc #(.CLK_HZ(SIM_CLK_HZ), .BAUD(SIM_BAUD), .BUILD_ID(32'h51a0_0003),
                .BOOT_HEX("build/fpga/boot_linuxsim.hex")) dut (
      .clk, .rst, .ddr_ready(1'b1), .ddr_soft(1'b0),
      .dcsr_req(), .dcsr_we(), .dcsr_addr(), .dcsr_wdata(), .dcsr_ack(1'b0), .dcsr_rdata(32'h0),
      .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_ack, .mem_rdata,
      .uart_tx, .uart_rx, .led, .dip(8'h00), .btn(5'h0),
      .mac_clk(clk), .mac_rst(rst), .mac_tx_clk(clk), .mac_tx_rst(rst), .tx_pcs_frames(16'h0), .rx_tdata, .rx_tvalid, .rx_tlast, .rx_tuser(1'b0),
      .tx_tdata, .tx_tvalid, .tx_tlast, .tx_tready(1'b1), .pcs_status(16'h0c03),
      .fl_addr(), .fl_dq_i(16'hffff), .fl_dq_o(), .fl_dq_t(), .fl_ce_n(), .fl_oe_n(), .fl_we_n(), .fl_adv_n(), .reconfig()
  );

  // ---------------------------------------------------------------- Ethernet peer
  logic [7:0] rx_tdata = 0, tx_tdata;
  logic       rx_tvalid = 0, rx_tlast = 0, tx_tvalid, tx_tlast;
  logic [7:0] txq[$], back[$][];
  longint     back_due[$];       // when each frame in back may go
  longint     sink_delay = 0;
  initial void'($value$plusargs("sinkdelay=%d", sink_delay));
  bit tcp_sink = 0;
  initial tcp_sink = $test$plusargs("tcpsink");
  logic [31:0] sink_nxt = 0;      // next sequence number expected
  bit          sink_open = 0, sink_fin = 0;
  int sink_segs = 0, sink_gaps = 0, sink_dups = 0, sink_bytes = 0;

  // an acknowledgement (or SYN-ACK, with an MSS option) from the sink for the segment in f
  function automatic void sink_reply(input logic [7:0] f[$], input int l4, input logic [7:0] flags);
    automatic int hl = flags[1] ? 24 : 20, n = 14 + 20 + hl;
    automatic logic [7:0] r[] = new[60];
    automatic logic [31:0] seq = flags[1] ? 32'h0000_1000 : 32'h0000_1001 + 32'(sink_fin && !flags[0]);
    automatic logic [15:0] c;
    automatic logic [7:0] q[$];
    for (int i = 0; i < 60; i++) r[i] = 8'h00;
    for (int i = 0; i < 6; i++) begin r[i] = f[6 + i]; r[6 + i] = f[i]; end
    r[12] = 8'h08; r[14] = 8'h45; r[16] = 8'(( 20 + hl) >> 8); r[17] = 8'(20 + hl); r[20] = 8'h40; r[22] = 8'd64; r[23] = 8'd6;
    for (int i = 0; i < 4; i++) begin r[26 + i] = f[30 + i]; r[30 + i] = f[26 + i]; end
    r[34] = f[l4 + 2]; r[35] = f[l4 + 3]; r[36] = f[l4]; r[37] = f[l4 + 1];
    for (int i = 0; i < 4; i++) begin r[38 + i] = seq[8*(3-i)+:8]; r[42 + i] = sink_nxt[8*(3-i)+:8]; end
    r[46] = 8'(hl << 2); r[47] = flags; r[48] = 8'hff; r[49] = 8'hff;
    if (flags[1]) begin r[54] = 8'd2; r[55] = 8'd4; r[56] = 8'h05; r[57] = 8'hb4; end      // MSS 1460
    for (int i = 0; i < n; i++) q.push_back(r[i]);
    c = ~csum(q, 14, 20, 0);  r[24] = c[15:8]; r[25] = c[7:0];
    c = ~csum(q, 34, hl, {16'b0, r[26], r[27]} + {16'b0, r[28], r[29]} + {16'b0, r[30], r[31]} + {16'b0, r[32], r[33]} + 32'd6 + 32'(hl));
    r[50] = c[15:8]; r[51] = c[7:0];
    back.push_back(r); back_due.push_back(cycles + sink_delay);
  endfunction

  function automatic void sink_segment(input logic [7:0] f[$], input int l4, input int l4len);
    automatic logic [31:0] seq = {f[l4 + 4], f[l4 + 5], f[l4 + 6], f[l4 + 7]};
    automatic int len = l4len - int'(f[l4 + 12][7:4]) * 4;
    automatic logic [7:0] fl = f[l4 + 13];
    if (fl[2]) begin sink_open = 0; return; end                                // RST
    if (fl[1]) begin                                                           // SYN
      sink_nxt = seq + 32'd1; sink_open = 1; sink_fin = 0;
      sink_reply(f, l4, 8'h12);
      return;
    end
    if (!sink_open || (len == 0 && !fl[0])) return;                            // a bare ACK
    sink_segs++;
    if (seq == sink_nxt) begin
      sink_nxt = sink_nxt + 32'(len) + 32'(fl[0]);
      sink_bytes += len;
      if (fl[0]) begin sink_reply(f, l4, 8'h11); sink_fin = 1; return; end
    end else if (int'(seq - sink_nxt) > 0) begin
      sink_gaps++;
      if (sink_gaps <= 20) $display("\n@@ SINK: frame %0d: sequence %0d bytes ahead of what has arrived (%0d bytes in this segment, %0d received so far)",
                                    eth_frames, seq - sink_nxt, len, sink_bytes);
    end else sink_dups++;
    sink_reply(f, l4, 8'h10);
  endfunction

  int eth_frames = 0, eth_ip_ok = 0, eth_ip_bad = 0, eth_l4_ok = 0, eth_l4_bad = 0, eth_reflected = 0, eth_arp = 0, eth_longest = 0, eth_full = 0;

  function automatic logic [15:0] csum(input logic [7:0] d[$], input int from, input int len, input logic [31:0] init);
    logic [31:0] s = init;
    for (int i = 0; i < len; i += 2) s += {16'b0, d[from + i], (i + 1 < len) ? d[from + i + 1] : 8'h00};
    while (s[31:16] != 0) s = {16'b0, s[15:0]} + {16'b0, s[31:16]};
    return s[15:0];
  endfunction

  task automatic eth_frame(input logic [7:0] f[$]);
    automatic int n = f.size();
    eth_frames++;
    if (n > eth_longest) eth_longest = n;
    if (n >= 1514) eth_full++;
    if (n >= 42 && f[12] == 8'h08 && f[13] == 8'h06 && f[21] == 8'h01) begin
      // ARP request: whoever is asked for is at 02:00:00:00:00:99
      automatic logic [7:0] r[] = new[60];
      automatic logic [47:0] peer = 48'h9900_0000_0002;
      for (int i = 0; i < 60; i++) r[i] = i < 42 ? f[i] : 8'h00;
      for (int i = 0; i < 6; i++) begin r[i] = f[6 + i]; r[6 + i] = peer[8*i+:8]; r[22 + i] = peer[8*i+:8]; r[32 + i] = f[22 + i]; end
      r[21] = 8'h02;
      for (int i = 0; i < 4; i++) begin r[28 + i] = f[38 + i]; r[38 + i] = f[28 + i]; end
      back.push_back(r); back_due.push_back(cycles);
      eth_arp++;
    end else if (n >= 34 && f[12] == 8'h08 && f[13] == 8'h00 && f[14][7:4] == 4'h4) begin
      automatic int ihl = int'(f[14][3:0]) * 4, tot = {f[16], f[17]}, l4 = 14 + ihl, l4len = tot - ihl;
      automatic bit frag = ({f[20], f[21]} & 16'h3fff) != 0;
      if (csum(f, 14, ihl, 0) == 16'hffff) eth_ip_ok++;
      else begin eth_ip_bad++; $display("\n@@ ETH ERROR: frame %0d (%0d bytes): bad IPv4 header checksum", eth_frames, n); end
      if (14 + tot > n) $display("\n@@ ETH ERROR: frame %0d: %0d bytes, IPv4 length %0d", eth_frames, n, tot);
      else if (!frag && (f[23] == 8'd6 || f[23] == 8'd17)) begin
        // pseudo-header: addresses, protocol, length
        automatic logic [31:0] ph = {16'b0, f[26], f[27]} + {16'b0, f[28], f[29]} + {16'b0, f[30], f[31]} + {16'b0, f[32], f[33]}
                                    + {24'b0, f[23]} + 32'(l4len);
        if (csum(f, l4, l4len, ph) == 16'hffff) eth_l4_ok++;
        else begin
          eth_l4_bad++;
          $display("\n@@ ETH ERROR: frame %0d (%0d bytes, protocol %0d, %0d bytes of it): bad checksum, field %02x%02x", eth_frames, n, f[23], l4len,
                   f[l4 + (f[23] == 8'd6 ? 16 : 6)], f[l4 + (f[23] == 8'd6 ? 17 : 7)]);
        end
        if (f[23] == 8'd6 && tcp_sink) sink_segment(f, l4, l4len);
        else if (f[23] == 8'd6) begin
          automatic logic [7:0] r[] = new[n < 60 ? 60 : n];
          for (int i = 0; i < r.size(); i++) r[i] = i < n ? f[i] : 8'h00;
          for (int i = 0; i < 6; i++) begin r[i] = f[6 + i]; r[6 + i] = f[i]; end
          for (int i = 0; i < 4; i++) begin r[26 + i] = f[30 + i]; r[30 + i] = f[26 + i]; end
          for (int i = 0; i < 2; i++) begin r[l4 + i] = f[l4 + 2 + i]; r[l4 + 2 + i] = f[l4 + i]; end
          back.push_back(r); back_due.push_back(cycles);
          eth_reflected++;
        end
      end
    end
  endtask

  always @(posedge clk) if (tx_tvalid) begin
    txq.push_back(tx_tdata);
    if (tx_tlast) begin eth_frame(txq); txq.delete(); end
  end
  initial forever begin
    @(posedge clk);
    if (back.size() != 0 && cycles >= back_due[0]) begin
      automatic logic [7:0] r[] = back.pop_front();
      void'(back_due.pop_front());
      for (int i = 0; i < r.size(); i++) begin
        rx_tdata <= r[i]; rx_tvalid <= 1; rx_tlast <= i == r.size() - 1;
        @(posedge clk);
      end
      rx_tvalid <= 0; rx_tlast <= 0;
      repeat (24) @(posedge clk);
    end
  end
  final if (tcp_sink) $display("@@ sink: %0d data segments, %0d bytes in order, %0d segments ahead of sequence (something before them was missing), %0d repeats",
                               sink_segs, sink_bytes, sink_gaps, sink_dups);
  final $display("@@ ethernet: %0d frames sent by the SoC (longest %0d bytes, %0d full size), %0d ARP answered, IPv4 header checksums %0d good %0d bad, TCP/UDP checksums %0d good %0d bad, %0d TCP segments sent back, dropped by the receiver %0d",
                 eth_frames, eth_longest, eth_full, eth_arp, eth_ip_ok, eth_ip_bad, eth_l4_ok, eth_l4_bad, eth_reflected, dut.u_eth.rx_dropped);

  // ---------------------------------------------------------------- memory
  logic [511:0] lines[int];
  task automatic preload(input string spec);
    string file;
    longint addr, n = 0;
    int fd, at, c;
    int ln;
    at = -1;
    for (int i = 0; i < spec.len(); i++) if (spec[i] == "@") at = i;
    if (at < 0) $fatal(1, "bad +load spec %s", spec);
    file = spec.substr(0, at - 1);
    addr = 0;   // atohex() is only 32 bits wide
    void'($sscanf(spec.substr(at + 1, spec.len() - 1), "%h", addr));
    fd = $fopen(file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", file);
    addr = addr - 64'h8000_0000;
    forever begin
      c = $fgetc(fd);
      if (c < 0) break;
      ln = int'(addr >> 6);
      if (!lines.exists(ln)) lines[ln] = '0;
      lines[ln][8*addr[5:0]+:8] = 8'(c);
      addr++; n++;
    end
    $fclose(fd);
    $display("@@ loaded %s: %0d bytes", spec, n);
  endtask

  int delay = 0;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (mem_req && !mem_ack) begin
      delay <= delay + 1;
      if (delay == 6) begin
        if (mem_we) begin lines[int'(mem_addr)] = mem_wdata; writes <= writes + 1; end
        else begin mem_rdata <= lines.exists(int'(mem_addr)) ? lines[int'(mem_addr)] : '0; reads <= reads + 1; end
        mem_ack <= 1;
      end
    end else begin
      delay <= 0;
      if (!mem_req) mem_ack <= 0;
    end
    if (progress != 0 && cycles % progress == 0 && cycles != 0)
      $display("\n@@ cycle %0d: pc=%016x priv=%0d instret=%0d satp=%0d", cycles, dut.u_core.ir_pc, dut.u_core.priv,
               dut.u_core.minstret, dut.u_core.satp_sv39);
    if (cycles > max_cycles) begin
      $display("\n@@ stopped at max_cycles: pc=%016x priv=%0d instret=%0d", dut.u_core.ir_pc, dut.u_core.priv, dut.u_core.minstret);
      $finish;
    end
  end

  // ---------------------------------------------------------------- UART trace (+uarttrace=<cycle>)
  longint trace_from = 0;
  initial void'($value$plusargs("uarttrace=%d", trace_from));
  logic irq_q = 0, pend_q = 0, sirq_q = 0;
  always @(posedge clk) if (trace_from != 0 && cycles >= trace_from) begin
    irq_q <= dut.u_uart.irq; pend_q <= dut.u_uart.thre_pending; sirq_q <= dut.irq_s_ext;
    if (dut.u_uart.irq != irq_q || dut.u_uart.thre_pending != pend_q || dut.irq_s_ext != sirq_q)
      $display("#%0d uart irq=%b pending=%b ier=%h thr_full=%b busy=%b  plic irq_s=%b pend=%b insvc=%b",
               cycles, dut.u_uart.irq, dut.u_uart.thre_pending, dut.u_uart.ier, dut.u_uart.thr_full, dut.u_uart.tx_busy,
               dut.irq_s_ext, dut.u_plic.pending[10], dut.u_plic.in_service[10]);
    if (dut.u_uart.sel) $display("#%0d uart %s reg %0d %s%h", cycles, dut.u_uart.we ? "write" : "read ", dut.u_uart.addr,
               dut.u_uart.we ? "" : "-> ", dut.u_uart.we ? dut.u_uart.wdata : dut.u_uart.rdata);
    if (dut.u_plic.sel && dut.u_plic.addr >= 26'h200000) $display("#%0d plic %s %h %h best=%0d pending=%h insvc=%h en=%h src=%h", cycles, dut.u_plic.we ? "write" : "read ", dut.u_plic.addr, dut.u_plic.wdata, dut.u_plic.best[1], dut.u_plic.pending, dut.u_plic.in_service, dut.u_plic.enable[1], dut.plic_src);
  end

  // ---------------------------------------------------------------- periodic state (+sample=<cycle>)
  longint sample_from = 0;
  initial void'($value$plusargs("sample=%d", sample_from));
  always @(posedge clk) if (sample_from != 0 && cycles >= sample_from && cycles % 1000000 == 0)
    $display("@%0d pc=%h priv=%0d sie=%b mie=%b stie=%b stip=%b mtie=%b mtip=%b mtime=%0d cmp=%0d seie=%b uart_irq=%b instret=%0d",
             cycles, dut.u_core.ir_pc, dut.u_core.priv, dut.u_core.mstatus_sie, dut.u_core.mstatus_mie, dut.u_core.mie_stie,
             dut.u_core.mip_stip, dut.u_core.mie_mtie, dut.irq_timer, dut.mtime, dut.mtimecmp, dut.u_core.mie_seie,
             dut.u_uart.irq, dut.u_core.minstret);

  // ---------------------------------------------------------------- console out
  always @(posedge clk) if (dut.u_uart.wr_thr) begin
    automatic byte c = dut.u_uart.wdata;
    $write("%c", c);
    $fflush();
    if (until_s.len() > 0) begin
      until_i = (c == until_s[until_i]) ? until_i + 1 : (c == until_s[0] ? 1 : 0);
      if (until_i == until_s.len()) begin
        $display("\n@@ reached \"%s\": cycles=%0d instret=%0d line reads=%0d writes=%0d", until_s, cycles, dut.u_core.minstret, reads, writes);
        $finish;
      end
    end
    if (after_s.len() > 0 && !typing) begin
      after_i = (c == after_s[after_i]) ? after_i + 1 : (c == after_s[0] ? 1 : 0);
      if (after_i == after_s.len()) typing = 1;
    end
  end

  // ---------------------------------------------------------------- console in
  localparam int BIT = SIM_CLK_HZ / SIM_BAUD;
  initial begin
    wait (typing);
    repeat (200000) @(posedge clk);
    for (int i = 0; i < type_s.len(); i++) begin
      automatic logic [7:0] ch = type_s[i] == "^" ? 8'h0a : type_s[i];
      uart_rx <= 0; repeat (BIT) @(posedge clk);
      for (int b = 0; b < 8; b++) begin uart_rx <= ch[b]; repeat (BIT) @(posedge clk); end
      uart_rx <= 1; repeat (BIT * 40) @(posedge clk);
    end
  end

  initial begin
    string spec;
    void'($value$plusargs("max_cycles=%d", max_cycles));
    void'($value$plusargs("progress=%d", progress));
    void'($value$plusargs("until=%s", until_s));
    void'($value$plusargs("type=%s", type_s));
    void'($value$plusargs("after=%s", after_s));
    if ($value$plusargs("load0=%s", spec)) preload(spec);
    if ($value$plusargs("load1=%s", spec)) preload(spec);
    if ($value$plusargs("load2=%s", spec)) preload(spec);
    if ($value$plusargs("load3=%s", spec)) preload(spec);
    repeat (20) @(posedge clk);
    rst <= 0;
  end
endmodule
