// SPDX-License-Identifier: Apache-2.0
// Unit test of legend_flash against a model of an asynchronous NOR flash that checks the bus
// timing: data is rubbish until the access time has passed since the address, CE or OE last
// changed, and a write is checked for pulse width, data set-up and hold, and a steady address.
// The model knows just enough commands to exercise both directions: read array (0xff), read
// status (0x70), read identifier (0x90) and word program (0x40, then the data).
//   -DCLK_HZ=12500000 runs the same test at another clock.
`timescale 1ns / 1ps
`ifndef CLK_HZ
`define CLK_HZ 50_000_000
`endif
module tb;
  localparam int CLK_HZ = `CLK_HZ;
  localparam real HALF = 0.5e9 / CLK_HZ;
  localparam real T_ACC = 96.0, T_WP = 50.0, T_DS = 50.0, T_WPH = 20.0;
  logic clk = 0, rst = 1;
  always #(HALF) clk = ~clk;

  logic        req = 0, we = 0, gnt;
  logic [24:1] addr = '0;
  logic [7:0]  be = '0;
  logic [63:0] wdata = '0, rdata;
  logic [23:0] fl_addr;
  logic [15:0] fl_dq_i, fl_dq_o;
  logic        fl_dq_t, fl_ce_n, fl_oe_n, fl_we_n, fl_adv_n;
  int errors = 0;

  legend_flash #(.CLK_HZ(CLK_HZ)) dut (.*);

  // ---------------------------------------------------------------- flash model
  logic [15:0] mem[int];
  typedef enum {M_ARRAY, M_STATUS, M_ID} mode_t;
  mode_t mode = M_ARRAY;
  bit    prog_next = 0;
  int    programs = 0, cmds = 0;
  realtime t_bus = 0, t_dq = 0, t_wl = 0, t_wh = 0, t_addr = 0;

  function automatic logic [15:0] value();
    case (mode)
      M_STATUS: return 16'h0080;
      M_ID:     return fl_addr[0] ? 16'h88b0 : 16'h0089;
      default:  return mem.exists(int'(fl_addr)) ? mem[int'(fl_addr)] : 16'hffff;
    endcase
  endfunction

  always @(fl_addr or fl_ce_n or fl_oe_n) t_bus = $realtime;
  always @(fl_addr) t_addr = $realtime;
  always @(fl_dq_o or fl_dq_t) t_dq = $realtime;
  always #1 fl_dq_i = (!fl_ce_n && !fl_oe_n && fl_dq_t && $realtime - t_bus >= T_ACC) ? value() : 16'h5a5a ^ fl_addr[15:0];

  task automatic bad(input string what);
    $display("ERROR at %0t: %s", $realtime, what); errors++;
  endtask
  always @(negedge fl_we_n) begin
    t_wl = $realtime;
    if (fl_ce_n) bad("write with CE high");
    if (!fl_oe_n) bad("write with OE low");
    if (t_wh != 0 && $realtime - t_wh < T_WPH) bad("WE high too short");
  end
  always @(posedge fl_we_n) if (!rst) begin
    t_wh = $realtime;
    if ($realtime - t_wl < T_WP) bad("write pulse too short");
    if (fl_dq_t) bad("data not driven at the end of the write pulse");
    if ($realtime - t_dq < T_DS) bad("data set-up too short");
    if (t_addr > t_wl) bad("address changed during the write pulse");
    if (prog_next) begin
      mem[int'(fl_addr)] = value_at(fl_addr) & fl_dq_o; prog_next = 0; mode = M_STATUS; programs++;
    end else begin
      cmds++;
      case (fl_dq_o[7:0])
        8'hff: mode = M_ARRAY;
        8'h70: mode = M_STATUS;
        8'h90: mode = M_ID;
        8'h40: prog_next = 1;
        default: bad($sformatf("unknown command %h", fl_dq_o));
      endcase
    end
    #0.5 if (fl_dq_t) bad("no data hold after the write pulse");
  end
  function automatic logic [15:0] value_at(input logic [23:0] a);
    return mem.exists(int'(a)) ? mem[int'(a)] : 16'hffff;
  endfunction
  always @(posedge clk) if (!rst && !fl_dq_t && !fl_oe_n) bad("both ends driving the data bus");
  always @(posedge clk) if (!rst && fl_adv_n) bad("ADV high");

  // ---------------------------------------------------------------- driver
  task automatic access(input bit w, input logic [24:0] a, input logic [7:0] b, input logic [63:0] d);
    @(posedge clk);
    req <= 1; we <= w; addr <= a[24:1]; be <= w ? b : 8'h00; wdata <= d;
    do @(posedge clk); while (!gnt);
    req <= 0;
    @(posedge clk);      // rdata is valid now
  endtask
  task automatic write16(input logic [24:0] a, input logic [15:0] d);
    access(1, a, 8'h03 << a[2:0], 64'(d) << (8 * a[2:0]));
  endtask
  // a read: every flash word from the addressed one to the end of the bus word must be right
  task automatic check_read(input logic [24:0] a, input mode_t m);
    logic [15:0] want;
    access(0, a, 0, 0);
    for (int l = int'(a[2:1]); l < 4; l++) begin
      logic [23:0] wa = {a[24:3], 2'(l)};
      want = m == M_STATUS ? 16'h0080 : m == M_ID ? (wa[0] ? 16'h88b0 : 16'h0089) : value_at(wa);
      if (rdata[16*l+:16] !== want) bad($sformatf("read %h lane %0d: got %h, want %h", a, l, rdata[16*l+:16], want));
    end
  endtask

  int n = 3000;
  logic [24:0] a;
  logic [23:0] hist[$];
  initial begin
    void'($value$plusargs("n=%d", n));
    repeat (5) @(posedge clk);
    rst <= 0;
    check_read(25'h0, M_ARRAY);
    write16(25'h0, 16'h0090); check_read(25'h0, M_ID); check_read(25'h2, M_ID);
    write16(25'h100, 16'h0070); check_read(25'h1fffffe, M_STATUS);
    write16(25'h0, 16'h00ff);
    // two programs in one 64-bit write: command, data, command, data
    access(1, 25'h40, 8'hff, 64'hbeef_0040_1234_0040);
    write16(25'h0, 16'h00ff);
    check_read(25'h40, M_ARRAY);
    if (value_at(24'h21) !== 16'h1234 || value_at(24'h23) !== 16'hbeef) bad("programs in one bus write");
    access(1, 25'h80, 8'h00, 64'h0);      // no byte enables: nothing happens
    for (int i = 0; i < n; i++) begin
      a = 25'($urandom) & ~25'h1;
      if (hist.size() > 0 && $urandom_range(3) == 0) a = {hist[$urandom_range(hist.size() - 1)], 1'b0} ^ 25'($urandom_range(3) << 1);
      case ($urandom_range(3))
        0, 1: begin
          write16(a, 16'h0040); write16(a, 16'($urandom));
          if ($urandom_range(1)) check_read(a, M_STATUS);
          write16(25'($urandom) & ~25'h1, 16'h00ff);
          hist.push_back(a[24:1]);
        end
        default: check_read(a, M_ARRAY);
      endcase
      repeat ($urandom_range(3)) @(posedge clk);
    end
    $display("%0d Hz: %0d programs, %0d commands, %0d errors", CLK_HZ, programs, cmds, errors);
    $display(errors == 0 ? "PASS" : "FAIL");
    $finish;
  end
endmodule
