// mig_line_adapter: turns the cache's line handshake into commands on the user interface of
// the Xilinx 7-series memory interface (4:1 mode, 64-bit DDR3: one 512-bit word per burst).
// Runs on ui_clk; the request comes from another clock domain and is synchronised here.
module mig_line_adapter #(
    parameter int LINE_BITS = 24,
    parameter int APP_AW    = 28
) (
    input  logic                 ui_clk,
    input  logic                 ui_rst,

    input  logic                 req,        // asynchronous, level
    input  logic                 we,
    input  logic [LINE_BITS-1:0] line,
    input  logic [511:0]         wdata,
    output logic                 ack,
    output logic [511:0]         rdata,

    output logic [APP_AW-1:0]    app_addr,
    output logic [2:0]           app_cmd,
    output logic                 app_en,
    output logic [511:0]         app_wdf_data,
    output logic                 app_wdf_end,
    output logic [63:0]          app_wdf_mask,
    output logic                 app_wdf_wren,
    input  logic [511:0]         app_rd_data,
    input  logic                 app_rd_data_valid,
    input  logic                 app_rdy,
    input  logic                 app_wdf_rdy
);
  typedef enum logic [1:0] {A_IDLE, A_CMD, A_WAIT, A_ACK} astate_e;
  astate_e state;
  logic req_s1, req_s2, cmd_done, wdf_done, we_q;

  assign app_addr     = APP_AW'({line, 3'b000});   // the interface counts 64-bit words
  assign app_cmd      = we_q ? 3'b000 : 3'b001;
  assign app_en       = state == A_CMD && !cmd_done;
  assign app_wdf_wren = state == A_CMD && we_q && !wdf_done;
  assign app_wdf_end  = app_wdf_wren;
  assign app_wdf_data = wdata;
  assign app_wdf_mask = '0;
  assign ack          = state == A_ACK;

  always_ff @(posedge ui_clk) begin
    req_s1 <= req;
    req_s2 <= req_s1;
    if (ui_rst) begin
      state <= A_IDLE;
    end else begin
      unique case (state)
        A_IDLE: if (req_s2) begin
          we_q <= we; cmd_done <= 1'b0; wdf_done <= 1'b0;
          state <= A_CMD;
        end
        A_CMD: begin
          if (app_en && app_rdy) cmd_done <= 1'b1;
          if (app_wdf_wren && app_wdf_rdy) wdf_done <= 1'b1;
          if ((cmd_done || app_rdy) && (!we_q || wdf_done || app_wdf_rdy)) state <= we_q ? A_ACK : A_WAIT;
        end
        A_WAIT: if (app_rd_data_valid) begin
          rdata <= app_rd_data;
          state <= A_ACK;
        end
        A_ACK: if (!req_s2) state <= A_IDLE;
      endcase
    end
  end
endmodule
