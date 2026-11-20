// SPDX-License-Identifier: Apache-2.0
// Simulation of legend64_soc with a behavioural line memory in place of the DDR3 controller and
// a scripted Ethernet peer in place of the MAC. Prints what the monitor writes to the UART.
//
// After the monitor's prompt appears the peer sends an ARP request, then a UDP loader "write"
// packet, and checks the two frames the monitor transmits in reply. This exercises the whole
// packet path: MAC stream -> FIFO -> DMA through the cache's device port -> software -> back.
`timescale 1ns / 1ps
module tb;
  logic clk = 0, mac_clk = 0, rst = 1;
  always #10 clk = ~clk;        // 50 MHz
  always #4 mac_clk = ~mac_clk; // 125 MHz
  logic         mem_req, mem_we, mem_ack = 0;
  logic [23:0]  mem_addr;
  logic [511:0] mem_wdata, mem_rdata;
  logic [7:0]   led, rx_tdata = 0, tx_tdata;
  logic         uart_tx, rx_tvalid = 0, rx_tlast = 0, tx_tvalid, tx_tlast, tx_tready = 1;
  longint cycles = 0, max_cycles = 400_000_000, reads = 0, writes = 0;
  bit self_test;

  legend64_soc #(.CLK_HZ(50_000_000), .BAUD(3_000_000), .BUILD_ID(32'h51a0_0002),
                .BOOT_HEX("build/fpga/boot_sim.hex")) dut (
      .clk, .rst, .ddr_ready(1'b1), .ddr_soft(1'b0),
      .dcsr_req(), .dcsr_we(), .dcsr_addr(), .dcsr_wdata(), .dcsr_ack(1'b0), .dcsr_rdata(32'h0),
      .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_ack, .mem_rdata,
      .uart_tx, .uart_rx(1'b1), .led, .dip(8'h00), .btn(5'h0),
      .mac_clk, .mac_rst(rst), .mac_tx_clk(mac_clk), .mac_tx_rst(rst), .tx_pcs_frames(16'h0), .rx_tdata, .rx_tvalid, .rx_tlast, .rx_tuser(1'b0),
      .tx_tdata, .tx_tvalid, .tx_tlast, .tx_tready, .pcs_status(16'h0c03)
  );

  // ---------------------------------------------------------------- memory
  logic [511:0] lines[int];
  int delay = 0;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (mem_req && !mem_ack) begin
      delay <= delay + 1;
      if (delay == 6) begin
        if (mem_we) begin lines[int'(mem_addr)] = mem_wdata; writes <= writes + 1; end
        else begin mem_rdata <= lines.exists(int'(mem_addr)) ? lines[int'(mem_addr)] : {16{32'hdeadbeef}}; reads <= reads + 1; end
        mem_ack <= 1;
      end
    end else begin
      delay <= 0;
      if (!mem_req) mem_ack <= 0;
    end
    if (cycles > max_cycles) begin $display("\n@@ timeout"); $finish; end
  end

  // ---------------------------------------------------------------- console
  bit prompt = 0;
  always @(posedge clk) if (dut.u_uart.wr_thr) begin
    $write("%c", dut.u_uart.wdata);
    if (dut.u_uart.wdata == ">") prompt <= 1;
  end

  // ---------------------------------------------------------------- Ethernet peer
  byte unsigned frame[$], got[$];
  task automatic send_frame();
    for (int i = 0; i < frame.size(); i++) begin
      @(posedge mac_clk);
      rx_tdata <= frame[i]; rx_tvalid <= 1; rx_tlast <= i == frame.size() - 1;
    end
    @(posedge mac_clk);
    rx_tvalid <= 0; rx_tlast <= 0;
  endtask
  task automatic recv_frame();
    got = {};
    forever begin
      @(posedge mac_clk);
      if (tx_tvalid && tx_tready) begin
        got.push_back(tx_tdata);
        if (tx_tlast) break;
      end
    end
  endtask
  function automatic void push_hex(input string s);
    for (int i = 0; i + 1 < s.len(); i += 2) frame.push_back(8'(s.substr(i, i + 1).atohex()));
  endfunction

  int errors = 0;
  initial begin
    void'($value$plusargs("max_cycles=%d", max_cycles));
    repeat (20) @(posedge clk);
    rst <= 0;
    // the monitor announces itself with a gratuitous ARP
    recv_frame();
    $display("\n@@ tx frame 1: %0d bytes, ethertype %02x%02x (gratuitous ARP expected: 42 bytes, 0806)", got.size(), got[12], got[13]);
    if (got.size() != 42 || got[12] != 8'h08 || got[13] != 8'h06) errors++;
    wait (prompt);
    // ARP request: who has 192.168.1.51, tell 192.168.1.176 (02:11:22:33:44:55)
    frame = {};
    push_hex("ffffffffffff021122334455080600010800060400010211223344");
    push_hex("55c0a801b0000000000000c0a80133");
    while (frame.size() < 60) frame.push_back(0);
    fork recv_frame(); send_frame(); join
    $display("@@ tx frame 2: %0d bytes, dst %02x:%02x:..:%02x, arp op %0d, sender ip %0d.%0d.%0d.%0d (ARP reply expected)",
             got.size(), got[0], got[1], got[5], got[21], got[28], got[29], got[30], got[31]);
    if (got.size() != 42 || got[21] != 2 || got[5] != 8'h55 || got[31] != 51) errors++;
    // UDP loader: write 16 bytes to 0x8000_2000
    frame = {};
    push_hex("020000fab1e5021122334455080045000044000040004011");
    push_hex("0000c0a801b0c0a80133");                        // checksum (unchecked), src, dst
    push_hex("3039194000300000");                            // udp: 12345 -> 6464, length 48
    push_hex("46424c310100000007000000002000800000000010000000"); // FBL1, write, seq 7, addr, len 16
    push_hex("00112233445566778899aabbccddeeff");
    fork recv_frame(); send_frame(); join
    $display("@@ tx frame 3: %0d bytes, udp dst port %0d, magic %c%c%c%c, command %02x, seq %0d (loader ack expected: 66 bytes, 81)",
             got.size(), {got[36], got[37]}, got[42], got[43], got[44], got[45], got[46], got[50]);
    if (got.size() != 66 || got[46] != 8'h81 || got[50] != 7) errors++;
    repeat (2000) @(posedge clk);
    $display("@@ done: errors=%0d cycles=%0d line reads=%0d line writes=%0d", errors, cycles, reads, writes);
    $finish;
  end
endmodule
