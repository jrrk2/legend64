// pico_fable: an RV32IM core that plugs into the PicoRV32 native memory interface.
//
// Designed from the PicoRV32 interface description, not derived from its RTL. Where PicoRV32
// is a multi-cycle state machine, this is a three-stage pipeline built around the fact that
// the native interface is a single memory port shared by instructions and data:
//
//   F  issue an instruction address on the look-ahead port
//   D  instruction arrives on mem_rdata; predict its successor and issue that fetch at once
//   X  read registers, execute, resolve the prediction, issue any load or store
//
// The port carries one transfer per cycle, so a load or store costs one extra cycle and
// everything else costs one. Predicted-taken branches, direct jumps and returns cost nothing
// extra; a misprediction costs two cycles.
//
// Supported: RV32IM, rdcycle[h]/rdinstret[h], trap output on ecall/ebreak/illegal/misaligned.
// Not implemented: PicoRV32's custom IRQ instructions, PCPI, compressed ISA, trace port.
// The parameters and ports for those exist so the module is a drop-in, but they are inert.

module pico_fable #(
	parameter [ 0:0] ENABLE_COUNTERS = 1,
	parameter [ 0:0] ENABLE_COUNTERS64 = 1,
	parameter [ 0:0] ENABLE_REGS_16_31 = 1,
	parameter [ 0:0] ENABLE_REGS_DUALPORT = 1,
	parameter [ 0:0] LATCHED_MEM_RDATA = 0,
	parameter [ 0:0] TWO_STAGE_SHIFT = 1,
	parameter [ 0:0] BARREL_SHIFTER = 0,
	parameter [ 0:0] TWO_CYCLE_COMPARE = 0,
	parameter [ 0:0] TWO_CYCLE_ALU = 0,
	parameter [ 0:0] COMPRESSED_ISA = 0,
	parameter [ 0:0] CATCH_MISALIGN = 1,
	parameter [ 0:0] CATCH_ILLINSN = 1,
	parameter [ 0:0] ENABLE_PCPI = 0,
	parameter [ 0:0] ENABLE_MUL = 1,
	parameter [ 0:0] ENABLE_FAST_MUL = 1,
	parameter [ 0:0] ENABLE_DIV = 1,
	parameter [ 0:0] ENABLE_IRQ = 0,
	parameter [ 0:0] ENABLE_IRQ_QREGS = 1,
	parameter [ 0:0] ENABLE_IRQ_TIMER = 1,
	parameter [ 0:0] ENABLE_TRACE = 0,
	parameter [ 0:0] REGS_INIT_ZERO = 0,
	parameter [31:0] MASKED_IRQ = 32'h 0000_0000,
	parameter [31:0] LATCHED_IRQ = 32'h ffff_ffff,
	parameter [31:0] PROGADDR_RESET = 32'h 0000_0000,
	parameter [31:0] PROGADDR_IRQ = 32'h 0000_0010,
	parameter [31:0] STACKADDR = 32'h ffff_ffff,
	// branch predictor sizing (not PicoRV32 parameters)
	parameter integer BHT_BITS = 7
) (
	input clk, resetn,
	output reg trap,

	output reg        mem_valid,
	output reg        mem_instr,
	input             mem_ready,

	output reg [31:0] mem_addr,
	output reg [31:0] mem_wdata,
	output reg [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata,

	// Look-Ahead Interface
	output            mem_la_read,
	output            mem_la_write,
	output     [31:0] mem_la_addr,
	output     [31:0] mem_la_wdata,
	output     [ 3:0] mem_la_wstrb,

	// Pico Co-Processor Interface (not implemented)
	output            pcpi_valid,
	output     [31:0] pcpi_insn,
	output     [31:0] pcpi_rs1,
	output     [31:0] pcpi_rs2,
	input             pcpi_wr,
	input      [31:0] pcpi_rd,
	input             pcpi_wait,
	input             pcpi_ready,

	// IRQ Interface (not implemented)
	input      [31:0] irq,
	output     [31:0] eoi,

	// Trace Interface (not implemented)
	output            trace_valid,
	output     [35:0] trace_data
);
	assign pcpi_valid = 0, pcpi_insn = 0, pcpi_rs1 = 0, pcpi_rs2 = 0;
	assign eoi = 0, trace_valid = 0, trace_data = 0;

	// A transfer issued last cycle is still waiting for the memory: freeze everything.
	wire stall = mem_valid && !mem_ready;
	wire run = resetn && !trap && !stall;

	// ---------------------------------------------------------------- state
	reg [31:0] pc_f;            // next sequential fetch address
	reg        pend_fetch;      // the transfer completing this cycle is an instruction fetch
	reg [31:0] pend_pc;

	reg        ir_valid;        // instruction in X
	reg [31:0] ir, ir_pc, ir_pnpc;
	reg        skid_valid;      // instruction that arrived while X was busy
	reg [31:0] skid, skid_pc, skid_pnpc;

	localparam X_IDLE = 2'd0, X_LOAD = 2'd1, X_MUL = 2'd2, X_DIV = 2'd3;
	reg [1:0]  x_state;
	reg        init_sp;

	reg [63:0] count_cycle, count_instr;

	reg [31:0] regs [0:31];

	// ---------------------------------------------------------------- X: decode
	wire [6:0] opcode = ir[6:0];
	wire [2:0] funct3 = ir[14:12];
	wire [4:0] rd  = ir[11:7];
	wire [4:0] rs1 = ir[19:15];
	wire [4:0] rs2 = ir[24:20];

	wire is_lui    = opcode == 7'b0110111;
	wire is_auipc  = opcode == 7'b0010111;
	wire is_jal    = opcode == 7'b1101111;
	wire is_jalr   = opcode == 7'b1100111 && funct3 == 3'b000;
	wire is_branch = opcode == 7'b1100011 && funct3[2:1] != 2'b01;
	wire is_load   = opcode == 7'b0000011 && (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 ||
	                                           funct3 == 3'b100 || funct3 == 3'b101);
	wire is_store  = opcode == 7'b0100011 && (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010);
	wire is_opimm  = opcode == 7'b0010011 &&
	                 (funct3 == 3'b001 ? ir[31:25] == 7'b0000000 :
	                  funct3 == 3'b101 ? (ir[31:25] == 7'b0000000 || ir[31:25] == 7'b0100000) : 1'b1);
	wire is_op     = opcode == 7'b0110011 &&
	                 (ir[31:25] == 7'b0000000 || (ir[31:25] == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)));
	wire is_muldiv = opcode == 7'b0110011 && ir[31:25] == 7'b0000001;
	wire is_mul    = is_muldiv && !funct3[2] && ENABLE_MUL;
	wire is_div    = is_muldiv &&  funct3[2] && ENABLE_DIV;
	wire is_fence  = opcode == 7'b0001111 && funct3[2:1] == 2'b00;  // fence, fence.i
	wire is_rdctr  = opcode == 7'b1110011 && funct3 == 3'b010 && rs1 == 5'd0 && ENABLE_COUNTERS;
	wire is_rdcycle   = is_rdctr && (ir[31:20] == 12'hC00 || ir[31:20] == 12'hC01);
	wire is_rdcycleh  = is_rdctr && (ir[31:20] == 12'hC80 || ir[31:20] == 12'hC81) && ENABLE_COUNTERS64;
	wire is_rdinstr   = is_rdctr && ir[31:20] == 12'hC02;
	wire is_rdinstrh  = is_rdctr && ir[31:20] == 12'hC82 && ENABLE_COUNTERS64;
	wire is_counter   = is_rdcycle | is_rdcycleh | is_rdinstr | is_rdinstrh;
	wire is_legal  = is_lui | is_auipc | is_jal | is_jalr | is_branch | is_load | is_store |
	                 is_opimm | is_op | is_mul | is_div | is_fence | is_counter;

	wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
	wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
	wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
	wire [31:0] imm_u = {ir[31:12], 12'b0};
	wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

	wire [31:0] rs1v = rs1 == 5'd0 ? 32'd0 : regs[rs1];
	wire [31:0] rs2v = rs2 == 5'd0 ? 32'd0 : regs[rs2];

	// ---------------------------------------------------------------- X: ALU
	wire        alu_imm = is_opimm;
	wire [31:0] alu_b   = alu_imm ? imm_i : rs2v;
	wire        alu_sub = is_op && ir[30];
	wire [31:0] alu_add = alu_sub ? rs1v - rs2v : rs1v + alu_b;
	wire        lt_s    = $signed(rs1v) < $signed(alu_b);
	wire        lt_u    = rs1v < alu_b;
	wire [4:0]  shamt   = alu_b[4:0];
	wire [31:0] sh_l    = rs1v << shamt;
	wire [31:0] sh_r    = $signed({ir[30] & rs1v[31], rs1v}) >>> shamt;
	reg  [31:0] alu_out;
	always @* begin
		case (funct3)
			3'b000: alu_out = alu_add;
			3'b001: alu_out = sh_l;
			3'b010: alu_out = {31'b0, lt_s};
			3'b011: alu_out = {31'b0, lt_u};
			3'b100: alu_out = rs1v ^ alu_b;
			3'b101: alu_out = sh_r;
			3'b110: alu_out = rs1v | alu_b;
			default: alu_out = rs1v & alu_b;
		endcase
	end

	// ---------------------------------------------------------------- X: branches and jumps
	wire br_eq  = rs1v == rs2v;
	wire br_lt  = $signed(rs1v) < $signed(rs2v);
	wire br_ltu = rs1v < rs2v;
	reg  br_taken;
	always @* begin
		case (funct3)
			3'b000: br_taken = br_eq;
			3'b001: br_taken = !br_eq;
			3'b100: br_taken = br_lt;
			3'b101: br_taken = !br_lt;
			3'b110: br_taken = br_ltu;
			default: br_taken = !br_ltu;
		endcase
	end
	wire [31:0] pc_plus4  = ir_pc + 32'd4;
	wire [31:0] pc_target = ir_pc + (is_jal ? imm_j : imm_b);
	wire [31:0] jalr_sum  = rs1v + imm_i;
	wire [31:0] x_npc = is_jalr ? {jalr_sum[31:1], 1'b0} :
	                    (is_jal || (is_branch && br_taken)) ? pc_target : pc_plus4;
	wire        x_ctrl = is_jal | is_jalr | is_branch;

	// ---------------------------------------------------------------- X: load / store
	wire [31:0] ea = rs1v + (is_store ? imm_s : imm_i);
	wire ea_misaligned = funct3[1:0] == 2'b01 ? ea[0] : funct3[1:0] == 2'b10 ? |ea[1:0] : 1'b0;
	reg [31:0] st_data;
	reg [3:0]  st_strb;
	always @* begin
		case (funct3[1:0])
			2'b00:   begin st_data = {4{rs2v[7:0]}};  st_strb = 4'b0001 << ea[1:0]; end
			2'b01:   begin st_data = {2{rs2v[15:0]}}; st_strb = ea[1] ? 4'b1100 : 4'b0011; end
			default: begin st_data = rs2v;            st_strb = 4'b1111; end
		endcase
	end
	reg [1:0] ld_off;
	reg [31:0] ld_data;
	always @* begin
		case (funct3[1:0])
			2'b00: begin
				case (ld_off)
					2'b00: ld_data = {{24{!funct3[2] & mem_rdata[ 7]}}, mem_rdata[ 7: 0]};
					2'b01: ld_data = {{24{!funct3[2] & mem_rdata[15]}}, mem_rdata[15: 8]};
					2'b10: ld_data = {{24{!funct3[2] & mem_rdata[23]}}, mem_rdata[23:16]};
					2'b11: ld_data = {{24{!funct3[2] & mem_rdata[31]}}, mem_rdata[31:24]};
				endcase
			end
			2'b01: ld_data = ld_off[1] ? {{16{!funct3[2] & mem_rdata[31]}}, mem_rdata[31:16]}
			                           : {{16{!funct3[2] & mem_rdata[15]}}, mem_rdata[15: 0]};
			default: ld_data = mem_rdata;
		endcase
	end

	// ---------------------------------------------------------------- X: multiply / divide
	reg [63:0] mul_p;
	wire mul_sa = rs1v[31] && (funct3[1:0] == 2'b01 || funct3[1:0] == 2'b10);
	wire mul_sb = rs2v[31] &&  funct3[1:0] == 2'b01;
	wire signed [65:0] mul_full = $signed({mul_sa, rs1v}) * $signed({mul_sb, rs2v});

	reg [31:0] div_rem, div_quo, div_den;
	reg [5:0]  div_cnt;
	reg        div_neg_q, div_neg_r;
	wire        div_signed = !funct3[0];
	wire [32:0] div_shift = {div_rem, div_quo[31]};
	wire [33:0] div_sub = {1'b0, div_shift} - {2'b0, div_den};
	wire [31:0] div_result = funct3[1] ? (div_neg_r ? -div_rem : div_rem)
	                                   : (div_neg_q ? -div_quo : div_quo);

	// ---------------------------------------------------------------- X: control
	wire x_go = ir_valid && x_state == X_IDLE;
	wire x_misaligned_pc = x_ctrl && x_npc[1] && CATCH_MISALIGN;
	wire x_trap = x_go && (!is_legal || x_misaligned_pc ||
	                       ((is_load || is_store) && ea_misaligned && CATCH_MISALIGN));
	wire x_load_req  = x_go && is_load  && !x_trap;
	wire x_store_req = x_go && is_store && !x_trap;
	wire x_single = is_lui | is_auipc | is_jal | is_jalr | is_branch | is_store | is_opimm | is_op |
	                is_fence | is_counter;
	wire x_done = ir_valid && !x_trap &&
	              ((x_state == X_IDLE && x_single) || x_state == X_LOAD || x_state == X_MUL ||
	               (x_state == X_DIV && div_cnt == 0));
	// fence/fence.i refetch what follows, so code written by earlier stores is seen
	wire x_redirect = x_done && (x_npc != ir_pnpc || is_fence);

	reg        rf_we;
	reg [31:0] rf_wdata;
	always @* begin
		rf_we = x_done && rd != 5'd0 && !is_branch && !is_store && !is_fence;
		case (1'b1)
			x_state == X_LOAD:  rf_wdata = ld_data;
			x_state == X_MUL:   rf_wdata = funct3[1:0] == 2'b00 ? mul_p[31:0] : mul_p[63:32];
			x_state == X_DIV:   rf_wdata = div_result;
			is_lui:             rf_wdata = imm_u;
			is_auipc:           rf_wdata = ir_pc + imm_u;
			is_jal | is_jalr:   rf_wdata = pc_plus4;
			is_rdcycle:         rf_wdata = count_cycle[31:0];
			is_rdcycleh:        rf_wdata = count_cycle[63:32];
			is_rdinstr:         rf_wdata = count_instr[31:0];
			is_rdinstrh:        rf_wdata = count_instr[63:32];
			default:            rf_wdata = alu_out;
		endcase
	end
	wire [4:0] rf_waddr = rd;

	// ---------------------------------------------------------------- D: arrival and prediction
	wire arr_valid = pend_fetch && !x_redirect;
	wire [31:0] a = mem_rdata;
	wire a_jal  = a[6:0] == 7'b1101111;
	wire a_jalr = a[6:0] == 7'b1100111;
	wire a_br   = a[6:0] == 7'b1100011;
	wire a_link_rd  = a[11:7]  == 5'd1 || a[11:7]  == 5'd5;
	wire a_link_rs1 = a[19:15] == 5'd1 || a[19:15] == 5'd5;
	wire a_call = (a_jal || a_jalr) && a_link_rd;
	wire a_ret  = a_jalr && a_link_rs1 && !a_link_rd;
	wire [31:0] a_imm_j = {{11{a[31]}}, a[31], a[19:12], a[20], a[30:21], 1'b0};
	wire [31:0] a_imm_b = {{19{a[31]}}, a[31], a[7], a[30:25], a[11:8], 1'b0};
	wire [31:0] a_pc4 = pend_pc + 32'd4;
	wire [31:0] a_tgt = pend_pc + (a_jal ? a_imm_j : a_imm_b);

	// two-bit counters for conditional branches, return-address stack for returns
	reg [1:0]  bht [0:(1<<BHT_BITS)-1];
	reg [31:0] ras0, ras1, ras2, ras3;
	wire [1:0] a_ctr = bht[pend_pc[BHT_BITS+1:2]];
	wire [31:0] a_pnpc = a_jal ? a_tgt : (a_br && a_ctr[1]) ? a_tgt : a_ret ? ras0 : a_pc4;

	// ---------------------------------------------------------------- F: port arbitration
	wire x_mem_req = x_load_req | x_store_req;
	wire ir_stays = ir_valid && !x_done;
	wire [1:0] occupancy = x_redirect ? 2'd0 : {1'b0, ir_stays} + {1'b0, skid_valid} + {1'b0, arr_valid};
	wire fetch_req = !x_mem_req && !x_trap && occupancy <= 2'd1;
	wire [31:0] fetch_pc = x_redirect ? x_npc : arr_valid ? a_pnpc : pc_f;

	assign mem_la_read  = run && (fetch_req || x_load_req);
	assign mem_la_write = run && x_store_req;
	assign mem_la_addr  = x_mem_req ? {ea[31:2], 2'b00} : fetch_pc;
	assign mem_la_wdata = st_data;
	assign mem_la_wstrb = x_store_req ? st_strb : 4'b0000;

	// ---------------------------------------------------------------- sequential
	integer i;
	initial begin
		for (i = 0; i < (1<<BHT_BITS); i = i + 1) bht[i] = 2'b01;
	end

	always @(posedge clk) begin
		count_cycle <= resetn ? count_cycle + 1 : 0;

		if (!resetn) begin
			trap <= 0;
			mem_valid <= 0;
			mem_instr <= 0;
			mem_wstrb <= 0;
			pc_f <= PROGADDR_RESET;
			pend_fetch <= 0;
			ir_valid <= 0;
			skid_valid <= 0;
			x_state <= X_IDLE;
			init_sp <= ~STACKADDR != 0;
			count_instr <= 0;
		end else if (init_sp) begin
			regs[2] <= STACKADDR;
			init_sp <= 0;
		end else if (run) begin
			// memory port
			mem_valid <= mem_la_read || mem_la_write;
			mem_instr <= fetch_req;
			mem_addr  <= mem_la_addr;
			mem_wdata <= mem_la_wdata;
			mem_wstrb <= mem_la_wstrb;
			pend_fetch <= fetch_req;
			if (fetch_req) pend_pc <= fetch_pc;
			pc_f <= fetch_req ? fetch_pc + 32'd4 : fetch_pc;

			// instruction queue: IR <- skid <- arrival
			if (x_redirect) begin
				ir_valid <= 0;
				skid_valid <= 0;
			end else if (!ir_stays) begin
				if (skid_valid) begin
					ir <= skid; ir_pc <= skid_pc; ir_pnpc <= skid_pnpc;
					ir_valid <= 1;
					skid_valid <= 0;
				end else begin
					ir <= a; ir_pc <= pend_pc; ir_pnpc <= a_pnpc;
					ir_valid <= arr_valid;
				end
			end else if (arr_valid) begin
				skid <= a; skid_pc <= pend_pc; skid_pnpc <= a_pnpc;
				skid_valid <= 1;
			end

			// predictor state
			if (arr_valid) begin
				if (a_call) begin
					ras0 <= a_pc4; ras1 <= ras0; ras2 <= ras1; ras3 <= ras2;
				end else if (a_ret) begin
					ras0 <= ras1; ras1 <= ras2; ras2 <= ras3;
				end
			end
			if (x_done && is_branch) begin
				if (br_taken  && bht[ir_pc[BHT_BITS+1:2]] != 2'b11)
					bht[ir_pc[BHT_BITS+1:2]] <= bht[ir_pc[BHT_BITS+1:2]] + 2'd1;
				if (!br_taken && bht[ir_pc[BHT_BITS+1:2]] != 2'b00)
					bht[ir_pc[BHT_BITS+1:2]] <= bht[ir_pc[BHT_BITS+1:2]] - 2'd1;
			end

			// execute
			if (x_trap) trap <= 1;
			if (rf_we) regs[rf_waddr] <= rf_wdata;
			if (x_done) count_instr <= count_instr + 1;
			case (x_state)
				X_IDLE: if (ir_valid && !x_trap) begin
					if (is_load) begin
						x_state <= X_LOAD;
						ld_off <= ea[1:0];
					end
					if (is_mul) begin
						x_state <= X_MUL;
						mul_p <= mul_full[63:0];
					end
					if (is_div) begin
						x_state <= X_DIV;
						div_cnt <= 6'd32;
						div_rem <= 0;
						div_quo <= (div_signed && rs1v[31]) ? -rs1v : rs1v;
						div_den <= (div_signed && rs2v[31]) ? -rs2v : rs2v;
						div_neg_q <= div_signed && (rs1v[31] ^ rs2v[31]) && rs2v != 0;
						div_neg_r <= div_signed && rs1v[31];
					end
				end
				X_LOAD, X_MUL: x_state <= X_IDLE;
				X_DIV: begin
					if (div_cnt == 0) begin
						x_state <= X_IDLE;
					end else begin
						div_cnt <= div_cnt - 6'd1;
						if (!div_sub[33]) begin
							div_rem <= div_sub[31:0];
							div_quo <= {div_quo[30:0], 1'b1};
						end else begin
							div_rem <= div_shift[31:0];
							div_quo <= {div_quo[30:0], 1'b0};
						end
					end
				end
			endcase
		end
	end
endmodule
