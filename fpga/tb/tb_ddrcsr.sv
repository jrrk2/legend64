// Simulation of the LiteDRAM start-up path without a LiteDRAM: the full boot monitor runs
// LiteX's sdram_init() against a register file that simply stores what is written. Levelling
// cannot succeed, but every controller-register access goes through the SoC's stalled
// register window and its handshake, and the monitor must still reach its prompt.
`timescale 1ns / 1ps
module tb;
  logic clk = 0, mac_clk = 0, cclk = 0, rst = 1;
  always #10 clk = ~clk;
  always #4 mac_clk = ~mac_clk;
  always #5 cclk = ~cclk;       // the controller's 100 MHz clock
  logic         mem_req, mem_we, mem_ack = 0;
  logic [23:0]  mem_addr;
  logic [511:0] mem_wdata, mem_rdata;
  logic [7:0]   led, tx_tdata;
  logic         uart_tx, tx_tvalid, tx_tlast;
  logic         dcsr_req, dcsr_we, dcsr_ack = 0;
  logic [13:0]  dcsr_addr;
  logic [31:0]  dcsr_wdata, dcsr_rdata;
  longint cycles = 0, max_cycles = 300_000_000, csr_rd = 0, csr_wr = 0;

  fable64_soc #(.CLK_HZ(50_000_000), .BAUD(3_000_000), .BUILD_ID(32'h51a0_0003),
                .BOOT_HEX("build/fpga/boot.hex")) dut (
      .clk, .rst, .ddr_ready(1'b1), .ddr_soft(1'b1),
      .dcsr_req, .dcsr_we, .dcsr_addr, .dcsr_wdata, .dcsr_ack, .dcsr_rdata,
      .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_ack, .mem_rdata,
      .uart_tx, .uart_rx(1'b1), .led, .dip(8'h00), .btn(5'h0),
      .mac_clk, .mac_rst(rst), .mac_tx_clk(mac_clk), .mac_tx_rst(rst), .rx_tdata(8'h0), .rx_tvalid(1'b0), .rx_tlast(1'b0), .rx_tuser(1'b0),
      .tx_tdata, .tx_tvalid, .tx_tlast, .tx_tready(1'b1), .pcs_status(16'h0c03)
  );

  // controller registers, in their own clock domain
  logic [31:0] csr[int];
  logic [1:0]  creq_s = 0;
  int          cwait = 0;
  always @(posedge cclk) begin
    creq_s <= {creq_s[0], dcsr_req};
    if (creq_s[1] && !dcsr_ack) begin
      cwait <= cwait + 1;
      if (cwait == 2) begin
        if (dcsr_we) begin csr[int'(dcsr_addr)] = dcsr_wdata; csr_wr <= csr_wr + 1; end
        else begin dcsr_rdata <= csr.exists(int'(dcsr_addr)) ? csr[int'(dcsr_addr)] : 32'h0; csr_rd <= csr_rd + 1; end
        dcsr_ack <= 1;
      end
    end else begin
      cwait <= 0;
      if (!creq_s[1]) dcsr_ack <= 0;
    end
  end

  logic [511:0] lines[int];
  int delay = 0;
  always @(posedge clk) begin
    cycles <= cycles + 1;
    if (mem_req && !mem_ack) begin
      delay <= delay + 1;
      if (delay == 6) begin
        if (mem_we) lines[int'(mem_addr)] = mem_wdata;
        else mem_rdata <= lines.exists(int'(mem_addr)) ? lines[int'(mem_addr)] : {16{32'hdeadbeef}};
        mem_ack <= 1;
      end
    end else begin
      delay <= 0;
      if (!mem_req) mem_ack <= 0;
    end
    if (dut.u_uart.wr_thr) begin
      $write("%c", dut.u_uart.wdata);
      if (dut.u_uart.wdata == ">") begin
        $display("\n@@ prompt at %0d cycles; controller registers: %0d reads, %0d writes; init_done=%0d init_error=%0d",
                 cycles, csr_rd, csr_wr, csr.exists(0) ? csr[0] : -1, csr.exists(1) ? csr[1] : -1);
        $finish;
      end
    end
    if (cycles > max_cycles) begin $display("\n@@ timeout (%0d reads, %0d writes)", csr_rd, csr_wr); $finish; end
  end
  initial begin repeat (20) @(posedge clk); rst = 0; end
endmodule
