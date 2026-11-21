// SPDX-License-Identifier: Apache-2.0
// Testbench for legend64: 16 MB of RAM at 0x8000_0000, console at 0x1000_0000, HTIF-style
// tohost at 0x8000_1000 (as laid out by the riscv-tests linker script), and a CLINT-style
// timer (msip 0x0200_0000, mtimecmp 0x0200_4000, mtime 0x0200_bff8).
//
// +jitter randomises grant and read latency on both ports to exercise the bus handshakes.
// +ilat=<n> / +dlat=<n> add n cycles to every instruction / load answer (0..2): what a register
// in the memory's answer path would cost in cycles.
`timescale 1ns / 1ps

module tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        imem_req, imem_gnt, imem_rvalid = 0, dmem_req, dmem_we, dmem_gnt, dmem_rvalid = 0;
  logic [63:0] imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [31:0] imem_rdata;
  logic [7:0]  dmem_be;
  logic        tr_valid, tr_wen, tr_fwen;
  logic [63:0] tr_pc, tr_wdata;
  logic [31:0] tr_insn;
  logic [4:0]  tr_rd;
  logic        tr_trap, tr_trap_late, trap_pending = 0;
  logic [63:0] tr_cause, tr_epc, tr_tval, pend_cause, pend_epc, pend_tval;
  logic        msip = 0;
  logic [63:0] mtime = 0, mtimecmp = '1;

  legend64 uut (
      .clk, .rst_n,
      .imem_req, .imem_addr, .imem_gnt, .imem_rvalid, .imem_rdata,
      .dmem_req, .dmem_we, .dmem_addr, .dmem_wdata, .dmem_be, .dmem_gnt, .dmem_rvalid, .dmem_rdata,
      .irq_m_ext(1'b0), .irq_m_timer(mtime >= mtimecmp), .irq_m_soft(msip), .irq_s_ext(1'b0), .time_i(mtime),
      .tr_valid, .tr_pc, .tr_insn, .tr_wen, .tr_fwen, .tr_rd, .tr_wdata,
      .tr_trap, .tr_trap_late, .tr_cause, .tr_epc, .tr_tval
  );

  localparam int AW = 21;  // 64-bit words
  logic [63:0] memory[1 << AW];
  longint cycles = 0, retired = 0, max_cycles = 500_000_000;
  bit jitter, quiet;
  int ilat = 0, dlat = 0;
  int trace_fd = 0;
  string hex, trace_file;
  logic [63:0] tohost_addr = 64'h8000_1000;

  function automatic logic in_ram(input logic [63:0] addr);
    return addr[63:AW+3] == (64'h8000_0000 >> (AW + 3));
  endfunction
  function automatic logic [63:0] rd_word(input logic [63:0] addr);
    if (in_ram(addr)) return memory[addr[AW+2:3]];
    if (addr[63:3] == 61'h0200_bff8 >> 3) return mtime;
    if (addr[63:3] == 61'h0200_4000 >> 3) return mtimecmp;
    if (addr[63:3] == 61'h0200_0000 >> 3) return {63'b0, msip};
    return '0;
  endfunction

  task automatic finish_sim(input logic [63:0] code, input string why);
    $display("\n@@ %s code=%0d cycles=%0d instret=%0d", why, code, cycles, retired);
    if (trace_fd != 0) $fclose(trace_fd);
    $finish;
  endtask

  task automatic wr_word(input logic [63:0] addr, input logic [63:0] data, input logic [7:0] be);
    logic [63:0] nv;
    if (addr[63:3] == tohost_addr[63:3]) begin
      // riscv-tests writes tohost as two 32-bit halves; the low half carries (code << 1) | 1
      if (be[0] && data[0]) finish_sim(data >> 1, "exit");
    end else if (addr[63:3] == 61'h1000_0000 >> 3) begin
      if (!quiet && be[0]) $write("%c", data[7:0]);
    end else if (addr[63:3] == 61'h0200_4000 >> 3) begin
      mtimecmp <= data;
    end else if (addr[63:3] == 61'h0200_0000 >> 3) begin
      if (be[0]) msip <= data[0];
    end else if (in_ram(addr)) begin
      nv = memory[addr[AW+2:3]];
      for (int b = 0; b < 8; b++) if (be[b]) nv[8*b+:8] = data[8*b+:8];
      memory[addr[AW+2:3]] = nv;
    end
  endtask

  initial begin
    if (!$value$plusargs("hex=%s", hex)) $fatal(1, "need +hex=<file>");
    $readmemh(hex, memory);
    jitter = $test$plusargs("jitter");
    void'($value$plusargs("ilat=%d", ilat));
    void'($value$plusargs("dlat=%d", dlat));
    quiet  = $test$plusargs("quiet");
    void'($value$plusargs("max_cycles=%d", max_cycles));
    void'($value$plusargs("tohost=%h", tohost_addr));
    if ($value$plusargs("trace=%s", trace_file)) trace_fd = $fopen(trace_file, "w");
    repeat (10) @(posedge clk);
    rst_n <= 1;
  end

  // bus models
  logic        i_gnt_q = 1, d_gnt_q = 1, i_pend = 0, d_pend = 0;
  logic [1:0]  i_cnt, d_cnt;
  logic [63:0] i_addr, d_addr;
  assign imem_gnt = i_gnt_q;
  assign dmem_gnt = d_gnt_q;

  always @(posedge clk) begin
    int d;
    if (rst_n) cycles <= cycles + 1;
    mtime <= mtime + 1;
    i_gnt_q <= jitter ? ($urandom_range(0, 3) != 0) : 1'b1;
    d_gnt_q <= jitter ? ($urandom_range(0, 3) != 0) : 1'b1;

    imem_rvalid <= 0;
    if (i_pend) begin
      if (i_cnt == 0) begin
        imem_rvalid <= 1; i_pend <= 0;
        imem_rdata <= i_addr[2] ? 32'(rd_word(i_addr) >> 32) : 32'(rd_word(i_addr));
      end else i_cnt <= i_cnt - 1;
    end
    if (rst_n && imem_req && imem_gnt) begin
      d = jitter ? $urandom_range(0, 2) : ilat;
      if (d == 0) begin
        imem_rvalid <= 1;
        imem_rdata <= imem_addr[2] ? 32'(rd_word(imem_addr) >> 32) : 32'(rd_word(imem_addr));
      end else begin
        i_pend <= 1; i_cnt <= 2'(d - 1); i_addr <= imem_addr;
      end
    end

    dmem_rvalid <= 0;
    if (d_pend) begin
      if (d_cnt == 0) begin
        dmem_rvalid <= 1; d_pend <= 0; dmem_rdata <= rd_word(d_addr);
      end else d_cnt <= d_cnt - 1;
    end
    if (rst_n && dmem_req && dmem_gnt) begin
      if (dmem_we) begin
        wr_word(dmem_addr, dmem_wdata, dmem_be);
      end else begin
        d = jitter ? $urandom_range(0, 2) : dlat;
        if (d == 0) begin
          dmem_rvalid <= 1; dmem_rdata <= rd_word(dmem_addr);
        end else begin
          d_pend <= 1; d_cnt <= 2'(d - 1); d_addr <= dmem_addr;
        end
      end
    end

    if (tr_valid) begin
      retired <= retired + 1;
      if (trace_fd != 0) begin
        if (tr_wen)       $fwrite(trace_fd, "%016x %08x x%0d %016x\n", tr_pc, tr_insn, tr_rd, tr_wdata);
        else if (tr_fwen) $fwrite(trace_fd, "%016x %08x f%0d %016x\n", tr_pc, tr_insn, tr_rd, tr_wdata);
        else              $fwrite(trace_fd, "%016x %08x\n", tr_pc, tr_insn);
        if (trap_pending) $fwrite(trace_fd, "T %016x %016x %016x\n", pend_epc, pend_cause, pend_tval);
      end
      trap_pending <= 0;
    end
    // a trap is reported after any older instruction that has not retired yet
    if (tr_trap) begin
      if (tr_trap_late) begin trap_pending <= 1; pend_cause <= tr_cause; pend_epc <= tr_epc; pend_tval <= tr_tval; end
      else if (trace_fd != 0) $fwrite(trace_fd, "T %016x %016x %016x\n", tr_epc, tr_cause, tr_tval);
    end
    if (cycles > max_cycles) finish_sim(64'hffff_fffe, "timeout");
  end
endmodule
