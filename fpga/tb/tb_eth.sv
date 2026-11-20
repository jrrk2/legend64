// SPDX-License-Identifier: Apache-2.0
// Unit test of legend_eth against a byte-array memory and scripted MAC streams.
// Transmit: random frames of one to four descriptors at random byte alignments, with and without
// checksum insertion, some too long (to be discarded); the bytes that come out are compared
// with the expected frame, checksum computed here the textbook (big-endian) way.
// Receive: random frames; the buffer contents, length and checksum are checked. Both run at once
// so the two share the memory port.
//   +frames=<n>   frames each way (default 400)     +verilator+seed+<n>
//   +slowrx       be slow to return receive descriptors, so the hardware has to drop frames
//   +slowmem      grant the memory port rarely, so the receive FIFO fills (build with a small one)
// Built with -DREAL_MAC the transmit stream goes through the real byte-stream MAC (eth_mac_1g,
// from third_party/synthgui/projects/vc707_ethmin-src) and what is checked is its GMII output:
// preamble, frame, padding and FCS, and that it never flags a transmit error.
//   +minlen=<n>   no transmit frame shorter than n bytes (the real MAC cannot send a frame of
//                 one or two bytes: it takes two bytes before it looks at tlast)
//   +fastmem      memory always grants and answers in the next cycle, like a cache hit: frames
//                 then reach the transmit FIFO faster than the MAC takes them, and it fills
`timescale 1ns / 1ps
`ifndef RX_FIFO_AW
`define RX_FIFO_AW 14          // +define+RX_FIFO_AW=8 makes the FIFO, not the ring, overflow
`endif
module tb;
  localparam int RX_FIFO_AW = `RX_FIFO_AW;
  logic clk = 0, mac_clk = 0, rst = 1;
  always #10 clk = ~clk;
  always #4 mac_clk = ~mac_clk;
  logic mac_tx_clk = 0;
  always #4.1 mac_tx_clk = ~mac_tx_clk;

  logic        reg_sel = 0, reg_we = 0;
  logic [7:0]  reg_addr = 0;
  logic [31:0] reg_wdata = 0, reg_rdata;
  logic        irq, e_req, e_we, e_gnt, e_rvalid = 0;
  logic [29:0] e_addr;
  logic [63:0] e_wdata, e_rdata = 0;
  logic [7:0]  e_be, rx_tdata = 0, tx_tdata;
  logic        rx_tvalid = 0, rx_tlast = 0, tx_tvalid, tx_tlast;
`ifdef REAL_MAC
  wire         tx_tready;
`else
  logic        tx_tready = 1;
`endif

  legend_eth #(.RX_FIFO_AW(RX_FIFO_AW)) dut (
      .clk, .rst, .reg_sel, .reg_we, .reg_addr, .reg_wdata, .reg_rdata, .irq,
      .e_req, .e_we, .e_addr, .e_wdata, .e_be, .e_gnt, .e_rvalid, .e_rdata,
      .mac_clk, .mac_rst(rst), .mac_tx_clk, .mac_tx_rst(rst), .tx_pcs_frames(16'h0), .rx_tdata, .rx_tvalid, .rx_tlast, .rx_tuser(1'b0),
      .tx_tdata, .tx_tvalid, .tx_tlast, .tx_tready, .pcs_status(16'h0001),
      .fl_addr(), .fl_dq_i(16'hffff), .fl_dq_o(), .fl_dq_t(), .fl_ce_n(), .fl_oe_n(), .fl_we_n(), .fl_adv_n(), .reconfig()
  );

  int nframes = 400, errors = 0;
  bit slow_rx = 0, slow_mem = 0, fast_mem = 0;
  int min_len = 1;               // +minlen=<n>: no transmit frame shorter than this
  localparam int MEMSZ = 1 << 20;
  logic [7:0] mem[MEMSZ];
  localparam int RX_RING = 32'h1000, TX_RING = 32'h2000, RX_BUF = 32'h10000, TX_AREA = 32'h40000;
  localparam int NRING = 64;
  localparam logic [47:0] MAC = 48'h0605_0403_0201;   // bytes 01 02 03 04 05 06 on the wire

  function automatic logic [63:0] rd64(input int a);
    for (int i = 0; i < 8; i++) rd64[8*i+:8] = mem[a + i];
  endfunction
  task automatic wr64(input int a, input logic [63:0] v);
    for (int i = 0; i < 8; i++) mem[a + i] = v[8*i+:8];
  endtask

  // ---------------------------------------------------------------- memory port: one request
  // at a time, granted at random, read data one to three cycles after the grant
  logic gnt_ok = 0;
  int   rd_wait = 0;
  logic [29:0] rd_addr;
  assign e_gnt = e_req && gnt_ok && rd_wait == 0;
  always @(posedge clk) begin
    gnt_ok   <= fast_mem ? 1'b1 : slow_mem ? $urandom_range(0, 15) == 0 : $urandom_range(0, 3) != 0;
    e_rvalid <= 0;
    if (e_req && e_gnt) begin
      if (e_addr[2:0] != 0) begin $display("ERROR: unaligned memory address %h", e_addr); errors++; end
      if (e_we) begin
        for (int i = 0; i < 8; i++) if (e_be[i]) mem[int'(e_addr) + i] = e_wdata[8*i+:8];
      end else begin
        // +fastmem: as the cache does on a hit, the data is there in the cycle after the grant
        if (fast_mem) begin e_rvalid <= 1; e_rdata <= rd64(int'(e_addr)); end
        else begin rd_addr <= e_addr; rd_wait <= $urandom_range(1, 3); end
      end
    end
    if (rd_wait != 0) begin
      rd_wait <= rd_wait - 1;
      if (rd_wait == 1) begin e_rvalid <= 1; e_rdata <= rd64(int'(rd_addr)); end
    end
  end

  // ---------------------------------------------------------------- register writes
  task automatic regw(input logic [7:0] a, input logic [31:0] v);
    @(posedge clk); reg_sel <= 1; reg_we <= 1; reg_addr <= a; reg_wdata <= v;
    @(posedge clk); reg_sel <= 0; reg_we <= 0;
  endtask
  // the two test threads ask for their tail register to be written; one process does it
  logic        rx_tail_req = 0, tx_tail_req = 0;
  logic [15:0] rx_tail_v, tx_tail_v;
  logic        up = 0;
  always begin
    @(posedge clk);
    if (up && rx_tail_req) begin rx_tail_req = 0; regw(8'h30, 32'(rx_tail_v)); end
    else if (up && tx_tail_req) begin tx_tail_req = 0; regw(8'h50, 32'(tx_tail_v)); end
  end

  // ---------------------------------------------------------------- checksums, two ways
  // the Internet checksum as the RFC describes it: big-endian 16-bit words
  function automatic logic [15:0] sum_be(input logic [7:0] d[], input int from, input int len);
    logic [31:0] s = 0;
    for (int i = from; i < len; i += 2) s += {16'b0, d[i], (i + 1 < len) ? d[i + 1] : 8'h00};
    while (s[31:16] != 0) s = {16'b0, s[15:0]} + {16'b0, s[31:16]};
    return s[15:0];
  endfunction
  function automatic logic [15:0] sum_le(input logic [7:0] d[], input int from, input int len);
    logic [15:0] b = sum_be(d, from, len);
    return {b[7:0], b[15:8]};
  endfunction

  // ---------------------------------------------------------------- transmit
  logic [7:0] exp_data[$][];
  int         tx_checked = 0, tx_sent = 0, tx_discards = 0, tx_csums = 0, tx_multi = 0;

`ifdef REAL_MAC
  // ---- the real MAC between the front end and the checker
  wire [7:0] gmii_txd;
  wire       gmii_tx_en, gmii_tx_er, mac_tready;
  assign tx_tready = mac_tready;
  eth_mac_1g #(.ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)) u_mac (
      .rx_clk(mac_clk), .rx_rst(rst), .tx_clk(mac_tx_clk), .tx_rst(rst),
      .tx_axis_tdata(tx_tdata), .tx_axis_tvalid(tx_tvalid), .tx_axis_tready(mac_tready),
      .tx_axis_tlast(tx_tlast), .tx_axis_tuser(1'b0),
      .rx_axis_tdata(), .rx_axis_tvalid(), .rx_axis_tlast(), .rx_axis_tuser(),
      .gmii_rxd(8'h0), .gmii_rx_dv(1'b0), .gmii_rx_er(1'b0),
      .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
      .rx_clk_enable(1'b1), .tx_clk_enable(1'b1), .rx_mii_select(1'b0), .tx_mii_select(1'b0),
      .rx_error_bad_frame(), .rx_error_bad_fcs(), .rx_fcs_reg(), .tx_fcs_reg(), .ifg_delay(8'd12));

  function automatic logic [31:0] crc32(input logic [7:0] d[$], input int n);
    logic [31:0] c = 32'hffff_ffff;
    for (int i = 0; i < n; i++) begin
      c = c ^ {24'b0, d[i]};
      for (int k = 0; k < 8; k++) c = c[0] ? (c >> 1) ^ 32'hedb8_8320 : c >> 1;
    end
    return ~c;
  endfunction

  logic [7:0] g[$];
  logic       en_q = 0;
  int         gmii_errs = 0, gap = 100, min_gap = 100000;
  always @(posedge mac_tx_clk) begin
    en_q <= gmii_tx_en;
    if (gmii_tx_en && gmii_tx_er) begin
      gmii_errs++;
      if (gmii_errs <= 5) $display("ERROR: the MAC flagged a transmit error in frame %0d (it saw its input go idle inside a frame)", tx_checked);
      errors++;
    end
    if (gmii_tx_en) begin
      if (!en_q && gap < min_gap) min_gap = gap;
      g.push_back(gmii_txd); gap = 0;
    end else begin
      gap++;
      if (en_q) begin
        automatic int n = g.size() - 12;          // without preamble and FCS
        automatic bit bad = 0;
        for (int i = 0; i < 7; i++) if (g[i] !== 8'h55) bad = 1;
        if (bad || g[7] !== 8'hd5) begin $display("ERROR: tx frame %0d: bad preamble", tx_checked); errors++; end
        for (int i = 0; i < 8; i++) void'(g.pop_front());
        if (n < 60) begin $display("ERROR: tx frame %0d: %0d bytes on the wire before the FCS", tx_checked, n); errors++; end
        else begin
          automatic logic [31:0] c = crc32(g, n);
          if ({g[n + 3], g[n + 2], g[n + 1], g[n]} !== c) begin $display("ERROR: tx frame %0d: bad FCS", tx_checked); errors++; end
        end
        if (exp_data.size() == 0) begin $display("ERROR: unexpected frame of %0d bytes", n); errors++; end
        else begin
          automatic logic [7:0] e[] = exp_data.pop_front();
          automatic int nbad = 0, want = e.size() < 60 ? 60 : e.size();
          if (want != n) begin
            $display("ERROR: tx frame %0d: %0d bytes, expected %0d", tx_checked, n, want); errors++;
          end else begin
            for (int i = 0; i < n; i++) if ((i < e.size() ? e[i] : 8'h00) !== g[i]) begin
              if (nbad < 4) $display("ERROR: tx frame %0d byte %0d of %0d: %02x, expected %02x", tx_checked, i, n, g[i], i < e.size() ? e[i] : 8'h00);
              nbad++;
            end
            if (nbad != 0) errors++;
          end
        end
        tx_checked++;
        g.delete();
      end
    end
  end
`else
  // what comes out of the MAC side
  logic [7:0] got[$];
  logic       in_frame = 0;
  always @(posedge mac_tx_clk) begin
    tx_tready <= fast_mem ? 1'b1 : $urandom_range(0, 7) != 0;
    if (in_frame && !tx_tvalid) begin $display("ERROR: gap inside a transmitted frame"); errors++; end
    if (tx_tvalid && tx_tready) begin
      got.push_back(tx_tdata);
      in_frame <= !tx_tlast;
      if (tx_tlast) begin
        if (exp_data.size() == 0) begin $display("ERROR: unexpected frame of %0d bytes", got.size()); errors++; end
        else begin
          automatic logic [7:0] e[] = exp_data.pop_front();
          automatic int bad = 0;
          if (e.size() != got.size()) begin
            $display("ERROR: tx frame %0d: %0d bytes, expected %0d", tx_checked, got.size(), e.size()); errors++;
          end else begin
            for (int i = 0; i < e.size(); i++) if (e[i] !== got[i]) begin
              if (bad < 4) $display("ERROR: tx frame %0d byte %0d of %0d: %02x, expected %02x", tx_checked, i, e.size(), got[i], e[i]);
              bad++;
            end
            if (bad != 0) errors++;
          end
        end
        tx_checked++;
        got.delete();
      end
    end
  end

`endif
  int tx_sw_head = 0, tx_alloc = TX_AREA;
  task automatic tx_frame();
    automatic int ndesc = $urandom_range(0, 9) < 5 ? 1 : $urandom_range(2, 4);
    automatic int total, kind = $urandom_range(0, 19);
    automatic logic [7:0] f[];
    automatic int cs = 0, co = 0, pos = 0;
    automatic bit csum = 0, discard = 0;
    automatic int lens[4];
    if (kind == 0)      total = $urandom_range(1519, 1700);          // too long
    else if (kind < 6)  total = $urandom_range(1, 80);
    else if (kind < 10) total = $urandom_range(1400, 1518);
    else                total = $urandom_range(1, 1518);
    if (total < min_len) total = min_len;
    discard = total > 1518;
    f = new[total];
    for (int i = 0; i < total; i++) f[i] = 8'($urandom);
    // split
    begin
      automatic int left = total;
      for (int d = 0; d < ndesc; d++) begin
        lens[d] = d == ndesc - 1 ? left : $urandom_range(0, left);
        if (lens[d] > 1518 && ndesc > 1) lens[d] = 1518;      // let the running total catch it
        left -= lens[d];
      end
      if (left != 0) lens[ndesc - 1] += left;
    end
    if (!discard && total >= 4 && $urandom_range(0, 2) != 0) begin
      csum = 1;
      cs = 2 * $urandom_range(0, (total > 256 ? 254 : total - 2) / 2);
      co = 2 * $urandom_range(0, 127);
      if ($urandom_range(0, 3) != 0 && cs + co + 2 > total) co = 2 * $urandom_range(0, (total - cs - 2) / 2);
      if (cs + co + 2 <= total) begin
        automatic logic [15:0] c = ~sum_be(f, cs, total);
        if (c == 16'h0) c = 16'hffff;
        tx_csums++;
        // into memory goes the frame as software wrote it; expected is the frame with the sum in
        for (int d = 0, p = 0; d < ndesc; d++) p += lens[d];
        begin
          automatic logic [7:0] e[] = new[total](f);
          e[cs + co] = c[15:8]; e[cs + co + 1] = c[7:0];
          exp_data.push_back(e);
        end
      end else exp_data.push_back(f);
    end else if (!discard) exp_data.push_back(f);
    if (discard) tx_discards++;
    if (ndesc > 1) tx_multi++;
    for (int d = 0; d < ndesc; d++) begin
      automatic int a = tx_alloc + $urandom_range(0, 7);
      automatic logic [31:0] flags = 0;
      for (int i = 0; i < lens[d]; i++) mem[a + i] = f[pos + i];
      pos += lens[d];
      tx_alloc = (a + lens[d] + 15) & ~7;
      if (tx_alloc > MEMSZ - 8192) tx_alloc = TX_AREA;
      flags[1] = d != ndesc - 1;
      if (d == 0 && csum) begin flags[2] = 1; flags[23:16] = 8'(cs); flags[31:24] = 8'(co); end
      wr64(TX_RING + 16 * tx_sw_head, 64'(a));
      wr64(TX_RING + 16 * tx_sw_head + 8, {flags, 32'(lens[d])});
      tx_sw_head = (tx_sw_head + 1) % NRING;
    end
    tx_sent++;
  endtask

  initial begin : tx_thread
    wait (up);
    while (tx_sent < nframes) begin
      // up to twelve frames at once: more than the transmit FIFO holds
      automatic int batch = $urandom_range(0, 3) == 0 ? $urandom_range(4, 12) : $urandom_range(1, 3), first = tx_sw_head, expect_out;
      for (int b = 0; b < batch; b++) tx_frame();
      tx_tail_v = 16'(tx_sw_head); tx_tail_req = 1;
      wait (!tx_tail_req);
      // every descriptor is marked done and the head catches up
      begin
        automatic int guard = 0;
        while (dut.tx_head != 16'(tx_sw_head) || dut.t_state != dut.T_IDLE) begin
          @(posedge clk); guard++;
          if (guard > 2_000_000) begin $display("ERROR: transmit stuck, head %0d tail %0d state %0d", dut.tx_head, tx_sw_head, dut.t_state); errors++; $finish; end
        end
      end
      for (int i = first; i != tx_sw_head; i = (i + 1) % NRING)
        if (!mem[TX_RING + 16 * i + 12][0]) begin $display("ERROR: tx descriptor %0d not marked done", i); errors++; end
      repeat ($urandom_range(0, 400)) @(posedge clk);
    end
    // let the MAC side drain
    repeat (40000) @(posedge mac_tx_clk);
    if (exp_data.size() != 0) begin $display("ERROR: %0d transmitted frames never appeared", exp_data.size()); errors++; end
    tx_done = 1;
  end
  logic tx_done = 0, rx_done = 0;

  // ---------------------------------------------------------------- receive
  logic [7:0] rxf[$][];
  int rx_put = 0, rx_checked = 0, rx_skipped = 0, rx_long = 0;
  initial begin : rx_sender
    wait (up);
    repeat (100) @(posedge mac_clk);
    for (int k = 0; k < nframes; k++) begin
      automatic int kind = $urandom_range(0, 9);
      // a few are over 1518 bytes: those the hardware must discard
      automatic int len = kind < 3 ? $urandom_range(14, 70) : kind < 6 ? $urandom_range(1400, 1518) :
                          $urandom_range(0, 30) == 0 ? $urandom_range(1519, 1800) : $urandom_range(14, 1518);
      automatic logic [7:0] f[] = new[len];
      for (int i = 0; i < len; i++) f[i] = 8'($urandom);
      if (k % 3 == 0) for (int i = 0; i < 6; i++) f[i] = 8'hff;      // broadcast
      else for (int i = 0; i < 6; i++) f[i] = MAC[8*i+:8];
      f[6] = 8'(k >> 8); f[7] = 8'(k);                               // sequence number
      if (len <= 1518) begin rxf.push_back(f); rx_put++; end else rx_long++;
      for (int i = 0; i < len; i++) begin
        rx_tdata <= f[i]; rx_tvalid <= 1; rx_tlast <= i == len - 1;
        @(posedge mac_clk);
      end
      rx_tvalid <= 0; rx_tlast <= 0;
      repeat ($urandom_range(12, kind == 9 ? 12 : 6000)) @(posedge mac_clk);
    end
    rx_sent_all = 1;
  end
  logic rx_sent_all = 0;

  initial begin : rx_checker
    automatic int cur = 0, tail = NRING - 1, idle = 0;
    wait (up);
    forever begin
      @(posedge clk);
      if (mem[RX_RING + 16 * cur + 12][0]) begin
        automatic logic [63:0] w = rd64(RX_RING + 16 * cur + 8);
        automatic int len = int'(w[31:0]);
        automatic int a = int'(rd64(RX_RING + 16 * cur)) + 2;
        automatic int seq = {mem[a + 6], mem[a + 7]};
        automatic logic [7:0] f[];
        idle = 0;
        // frames the hardware dropped for want of room are skipped, by sequence number
        while (rxf.size() != 0) begin
          f = rxf.pop_front();
          if ({f[6], f[7]} == 16'(seq)) break;
          rx_skipped++;
        end
        if (f.size() != len) begin $display("ERROR: rx frame %0d: length %0d, expected %0d", seq, len, f.size()); errors++; end
        else begin
          automatic int bad = 0;
          for (int i = 0; i < len; i++) if (mem[a + i] !== f[i]) bad++;
          if (bad != 0) begin $display("ERROR: rx frame %0d: %0d of %0d bytes differ", seq, bad, len); errors++; end
          if (!w[33]) begin $display("ERROR: rx frame %0d: no checksum flag", seq); errors++; end
          if (w[63:48] !== sum_le(f, 14, len)) begin
            $display("ERROR: rx frame %0d (%0d bytes): checksum %04x, expected %04x", seq, len, w[63:48], sum_le(f, 14, len)); errors++;
          end
        end
        rx_checked++;
        wr64(RX_RING + 16 * cur + 8, 64'h0);
        cur = (cur + 1) % NRING; tail = (tail + 1) % NRING;
        // sometimes let the ring run short, so frames queue in the FIFO
        if ($urandom_range(0, 9) == 0) repeat ($urandom_range(0, 3000)) @(posedge clk);
        if (slow_rx && $urandom_range(0, 3) == 0) repeat ($urandom_range(0, 60000)) @(posedge clk);
        rx_tail_v = 16'(tail); rx_tail_req = 1;
        wait (!rx_tail_req);
      end else if (rx_sent_all) begin
        idle++;
        if (idle > 200000) begin rx_done = 1; break; end
      end
    end
  end

  // ---------------------------------------------------------------- main
  initial begin
    void'($value$plusargs("frames=%d", nframes));
    slow_rx = $test$plusargs("slowrx");
    slow_mem = $test$plusargs("slowmem");
    fast_mem = $test$plusargs("fastmem");
    void'($value$plusargs("minlen=%d", min_len));
    for (int i = 0; i < MEMSZ; i++) mem[i] = 8'($urandom);
    for (int i = 0; i < NRING; i++) begin
      wr64(RX_RING + 16 * i, 64'(RX_BUF + 2048 * i));
      wr64(RX_RING + 16 * i + 8, 64'h0);
      wr64(TX_RING + 16 * i, 64'h0);
      wr64(TX_RING + 16 * i + 8, 64'h0);
    end
    repeat (20) @(posedge clk);
    rst <= 0;
    repeat (10) @(posedge clk);
    regw(8'h00, 32'h100);
    regw(8'h10, MAC[31:0]);   regw(8'h14, 32'(MAC[47:32]));
    regw(8'h20, RX_RING);     regw(8'h24, 0); regw(8'h28, NRING); regw(8'h30, NRING - 1);
    regw(8'h40, TX_RING);     regw(8'h44, 0); regw(8'h48, NRING);
    regw(8'h00, 32'h3);
    up = 1;
    wait (tx_done && rx_done);
    $display("transmit: %0d frames posted, %0d checked on the wire, %0d discarded as too long, %0d with checksum, %0d of several descriptors",
             tx_sent, tx_checked, tx_discards, tx_csums, tx_multi);
    $display("receive:  %0d frames sent, %0d checked, %0d dropped by the hardware (register says %0d)",
             rx_put, rx_checked, rx_skipped + rxf.size(), dut.rx_dropped);
    $display("          %0d over 1518 bytes sent (counter %0d), lost to a full FIFO %0d, total with the ring's drops %0d",
             rx_long, dut.cnt_long, dut.cnt_fifo, 32'(dut.cnt_fifo) + dut.rx_dropped);
    if (32'(dut.cnt_long) != rx_long) begin $display("ERROR: long frame count"); errors++; end
    if (32'(dut.cnt_fifo) + dut.rx_dropped != rx_skipped + rxf.size()) begin $display("ERROR: drop counters do not add up"); errors++; end
`ifdef REAL_MAC
    $display("          through the real MAC: %0d transmit errors flagged, shortest gap between frames %0d byte times", gmii_errs, min_gap);
    // 802.3: at least 12 byte times of idle between frames; a PHY or switch may drop what follows less
    if (min_gap < 12) begin $display("ERROR: inter-frame gap of %0d byte times, under the minimum of 12", min_gap); errors++; end
`endif
    if (tx_checked != tx_sent - tx_discards) begin $display("ERROR: transmit count"); errors++; end
    if (rx_checked + rx_skipped + rxf.size() != rx_put) begin $display("ERROR: receive count"); errors++; end
    if (errors == 0) $display("PASS"); else $display("FAIL: %0d errors", errors);
    $finish;
  end
  initial begin
    #2_000_000_000;
    $display("FAIL: timeout"); $finish;
  end
endmodule
