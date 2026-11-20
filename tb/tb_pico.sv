// Testbench shared by PicoRV32 (reference, -DREF) and pico_legend on the native memory interface.
//
// Memory model: by default the look-ahead model from PicoRV32's own dhrystone/testbench.v
// (synchronous RAM addressed by mem_la_addr, mem_ready tied high). +nola selects the model
// from dhrystone/testbench_nola.v (mem_valid/mem_ready handshake, two cycles per transfer).
//
// Devices: 0x1000_0000 putc, 0x2000_0000 exit(code), 0x3000_0000 cycle counter,
// 0x3000_0004 retired-instruction counter.
`timescale 1ns / 1ps

module tb;
  logic clk = 0;
  logic resetn = 0;
  always #5 clk = ~clk;

  wire        trap, mem_valid, mem_instr, mem_la_read, mem_la_write;
  wire [31:0] mem_addr, mem_wdata, mem_la_addr, mem_la_wdata;
  wire [3:0]  mem_wstrb, mem_la_wstrb;
  logic [31:0] mem_rdata;
  logic       ready_q = 0;
  bit         nola, quiet;
  wire        mem_ready = nola ? ready_q : 1'b1;

`ifdef REF
  picorv32 #(
      .BARREL_SHIFTER(1), .ENABLE_FAST_MUL(1), .ENABLE_DIV(1),
      .PROGADDR_RESET(32'h80)
  ) uut (
`else
  pico_legend #(
      .PROGADDR_RESET(32'h80)
  ) uut (
`endif
      .clk, .resetn, .trap,
      .mem_valid, .mem_instr, .mem_ready, .mem_addr, .mem_wdata, .mem_wstrb, .mem_rdata,
      .mem_la_read, .mem_la_write, .mem_la_addr, .mem_la_wdata, .mem_la_wstrb,
      .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
      .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
      .irq(32'b0), .eoi(), .trace_valid(), .trace_data()
  );

  localparam int AW = 17;
  logic [31:0] memory[0:(1<<AW)-1];
  longint cycles = 0;
  longint max_cycles = 200_000_000;
  int trace_fd = 0;
  string hex, trace_file;

  // architectural event probes for lockstep comparison
`ifdef REF
  wire        rf_we = uut.resetn && uut.cpuregs_write && |uut.latched_rd;
  wire [4:0]  rf_waddr = uut.latched_rd[4:0];
  wire [31:0] rf_wdata = uut.cpuregs_wrdata;
`else
  wire        rf_we = uut.run && uut.rf_we;
  wire [4:0]  rf_waddr = uut.rf_waddr;
  wire [31:0] rf_wdata = uut.rf_wdata;
`endif
  wire [31:0] instret = uut.count_instr[31:0];

  function automatic logic [31:0] rd_word(input logic [31:0] addr);
    if (addr == 32'h3000_0000) return cycles[31:0];
    if (addr == 32'h3000_0004) return instret;
    if (addr[31:AW+2] != 0) return 32'h0;
    return memory[addr[AW+1:2]];
  endfunction

  task automatic wr_word(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb);
    if (trace_fd != 0) $fwrite(trace_fd, "M %08x %x %08x\n", {addr[31:2], 2'b00}, strb,
                               data & {{8{strb[3]}}, {8{strb[2]}}, {8{strb[1]}}, {8{strb[0]}}});
    if (addr[31:2] == 30'h0400_0000) begin
      if (!quiet) $write("%c", data[7:0]);
    end else if (addr[31:2] == 30'h0800_0000) begin
      finish_sim(data, "exit");
    end else if (addr[31:AW+2] == 0) begin
      for (int b = 0; b < 4; b++) if (strb[b]) memory[addr[AW+1:2]][8*b+:8] <= data[8*b+:8];
    end
  endtask

  task automatic finish_sim(input logic [31:0] code, input string why);
    $display("\n@@ %s code=%0d cycles=%0d instret=%0d", why, code, cycles, instret);
    if (trace_fd != 0) $fclose(trace_fd);
    $finish;
  endtask

  initial begin
    if (!$value$plusargs("hex=%s", hex)) $fatal(1, "need +hex=<file>");
    $readmemh(hex, memory);
    nola = $test$plusargs("nola");
    quiet = $test$plusargs("quiet");
    void'($value$plusargs("max_cycles=%d", max_cycles));
    if ($value$plusargs("trace=%s", trace_file)) trace_fd = $fopen(trace_file, "w");
    repeat (10) @(posedge clk);
    resetn <= 1;
  end

  always @(posedge clk) begin
    if (resetn) cycles <= cycles + 1;
    if (trace_fd != 0 && rf_we) $fwrite(trace_fd, "R %0d %08x\n", rf_waddr, rf_wdata);
    if (!nola) begin
      if (mem_la_read) mem_rdata <= rd_word(mem_la_addr);
      if (mem_la_write) wr_word(mem_la_addr, mem_la_wdata, mem_la_wstrb);
    end else begin
      ready_q <= 0;
      if (mem_valid && !ready_q) begin
        ready_q <= 1;
        if (|mem_wstrb) wr_word(mem_addr, mem_wdata, mem_wstrb);
        else mem_rdata <= rd_word(mem_addr);
      end
    end
    if (resetn && trap) finish_sim(32'hffff_ffff, "trap");
    if (cycles > max_cycles) finish_sim(32'hffff_fffe, "timeout");
  end
endmodule
