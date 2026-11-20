// the fetch window of legend64.sv: parcels arriving are placed after the ones buffered
module win (
    input  logic [63:0] buf_data,
    input  logic [2:0]  buf_cnt,
    input  logic [31:0] arr_word,
    input  logic        arr_valid, pend_skip,
    output logic [63:0] win_data,
    output logic [2:0]  win_cnt
);
  always_comb begin
    win_data = buf_data;
    win_cnt  = buf_cnt;
    if (arr_valid) begin
      if (pend_skip) begin
        win_data[16*buf_cnt[1:0]+:16] = arr_word[31:16];
        win_cnt = buf_cnt + 3'd1;
      end else begin
        win_data[16*buf_cnt[1:0]+:32] = arr_word;
        win_cnt = buf_cnt + 3'd2;
      end
    end
  end
endmodule
