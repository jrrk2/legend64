// SPDX-License-Identifier: Apache-2.0
// legend_reconfig: reload the FPGA from its configuration flash, as if PROGRAM_B had been
// pulsed, by sending the IPROG command through the internal configuration port (UG470,
// "IPROG Reconfiguration"). The warm boot address is left at zero with the revision-select
// pins not driven, so the image is the one the board's switches select, as at power-on.
module legend_reconfig (
    input logic clk,
    input logic rst,
    input logic go            // level; once seen the sequence runs to the end
);
  function automatic logic [31:0] swap(input logic [31:0] w);   // the port takes each byte bit-reversed
    for (int i = 0; i < 32; i++) swap[i] = w[(i & ~7) | (7 - (i & 7))];
  endfunction

  logic [3:0]  step;
  logic        run;
  logic [31:0] word;
  always_comb
    case (step)
      4'd1:    word = 32'hFFFF_FFFF;   // dummy
      4'd2:    word = 32'hAA99_5566;   // sync
      4'd3:    word = 32'h2000_0000;   // no-op
      4'd4:    word = 32'h3002_0001;   // write WBSTAR
      4'd5:    word = 32'h0000_0000;
      4'd6:    word = 32'h3000_8001;   // write CMD
      4'd7:    word = 32'h0000_000F;   // IPROG
      default: word = 32'h2000_0000;   // no-op
    endcase

  always_ff @(posedge clk) begin
    if (rst) begin run <= 1'b0; step <= '0; end
    else if (!run) begin run <= go; step <= '0; end
    else if (step != 4'd15) step <= step + 1'b1;
  end

  // step 0 puts the port in write mode with it deselected; words go in on steps 1 to 8
  ICAPE2 #(.ICAP_WIDTH("X32")) u_icap (
      .CLK(clk), .CSIB(!(run && step >= 4'd1 && step <= 4'd8)), .RDWRB(!run), .I(swap(word)), .O()
  );
endmodule
