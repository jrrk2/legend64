// Behavioural RAMB36E1 for simulation: true dual port, widths 1, 9, 18 and 36 (same on both
// ports), no output registers, write modes READ_FIRST, WRITE_FIRST and NO_CHANGE.
module RAMB36E1 #(
    parameter RAM_MODE = "TDP", parameter WRITE_MODE_A = "WRITE_FIRST", parameter WRITE_MODE_B = "WRITE_FIRST",
    parameter integer READ_WIDTH_A = 0, parameter integer WRITE_WIDTH_A = 0,
    parameter integer READ_WIDTH_B = 0, parameter integer WRITE_WIDTH_B = 0,
    parameter integer DOA_REG = 0, parameter integer DOB_REG = 0,
    parameter [255:0] INIT_00 = 256'h0,
    parameter [255:0] INIT_01 = 256'h0,
    parameter [255:0] INIT_02 = 256'h0,
    parameter [255:0] INIT_03 = 256'h0,
    parameter [255:0] INIT_04 = 256'h0,
    parameter [255:0] INIT_05 = 256'h0,
    parameter [255:0] INIT_06 = 256'h0,
    parameter [255:0] INIT_07 = 256'h0,
    parameter [255:0] INIT_08 = 256'h0,
    parameter [255:0] INIT_09 = 256'h0,
    parameter [255:0] INIT_0A = 256'h0,
    parameter [255:0] INIT_0B = 256'h0,
    parameter [255:0] INIT_0C = 256'h0,
    parameter [255:0] INIT_0D = 256'h0,
    parameter [255:0] INIT_0E = 256'h0,
    parameter [255:0] INIT_0F = 256'h0,
    parameter [255:0] INIT_10 = 256'h0,
    parameter [255:0] INIT_11 = 256'h0,
    parameter [255:0] INIT_12 = 256'h0,
    parameter [255:0] INIT_13 = 256'h0,
    parameter [255:0] INIT_14 = 256'h0,
    parameter [255:0] INIT_15 = 256'h0,
    parameter [255:0] INIT_16 = 256'h0,
    parameter [255:0] INIT_17 = 256'h0,
    parameter [255:0] INIT_18 = 256'h0,
    parameter [255:0] INIT_19 = 256'h0,
    parameter [255:0] INIT_1A = 256'h0,
    parameter [255:0] INIT_1B = 256'h0,
    parameter [255:0] INIT_1C = 256'h0,
    parameter [255:0] INIT_1D = 256'h0,
    parameter [255:0] INIT_1E = 256'h0,
    parameter [255:0] INIT_1F = 256'h0,
    parameter [255:0] INIT_20 = 256'h0,
    parameter [255:0] INIT_21 = 256'h0,
    parameter [255:0] INIT_22 = 256'h0,
    parameter [255:0] INIT_23 = 256'h0,
    parameter [255:0] INIT_24 = 256'h0,
    parameter [255:0] INIT_25 = 256'h0,
    parameter [255:0] INIT_26 = 256'h0,
    parameter [255:0] INIT_27 = 256'h0,
    parameter [255:0] INIT_28 = 256'h0,
    parameter [255:0] INIT_29 = 256'h0,
    parameter [255:0] INIT_2A = 256'h0,
    parameter [255:0] INIT_2B = 256'h0,
    parameter [255:0] INIT_2C = 256'h0,
    parameter [255:0] INIT_2D = 256'h0,
    parameter [255:0] INIT_2E = 256'h0,
    parameter [255:0] INIT_2F = 256'h0,
    parameter [255:0] INIT_30 = 256'h0,
    parameter [255:0] INIT_31 = 256'h0,
    parameter [255:0] INIT_32 = 256'h0,
    parameter [255:0] INIT_33 = 256'h0,
    parameter [255:0] INIT_34 = 256'h0,
    parameter [255:0] INIT_35 = 256'h0,
    parameter [255:0] INIT_36 = 256'h0,
    parameter [255:0] INIT_37 = 256'h0,
    parameter [255:0] INIT_38 = 256'h0,
    parameter [255:0] INIT_39 = 256'h0,
    parameter [255:0] INIT_3A = 256'h0,
    parameter [255:0] INIT_3B = 256'h0,
    parameter [255:0] INIT_3C = 256'h0,
    parameter [255:0] INIT_3D = 256'h0,
    parameter [255:0] INIT_3E = 256'h0,
    parameter [255:0] INIT_3F = 256'h0,
    parameter [255:0] INIT_40 = 256'h0,
    parameter [255:0] INIT_41 = 256'h0,
    parameter [255:0] INIT_42 = 256'h0,
    parameter [255:0] INIT_43 = 256'h0,
    parameter [255:0] INIT_44 = 256'h0,
    parameter [255:0] INIT_45 = 256'h0,
    parameter [255:0] INIT_46 = 256'h0,
    parameter [255:0] INIT_47 = 256'h0,
    parameter [255:0] INIT_48 = 256'h0,
    parameter [255:0] INIT_49 = 256'h0,
    parameter [255:0] INIT_4A = 256'h0,
    parameter [255:0] INIT_4B = 256'h0,
    parameter [255:0] INIT_4C = 256'h0,
    parameter [255:0] INIT_4D = 256'h0,
    parameter [255:0] INIT_4E = 256'h0,
    parameter [255:0] INIT_4F = 256'h0,
    parameter [255:0] INIT_50 = 256'h0,
    parameter [255:0] INIT_51 = 256'h0,
    parameter [255:0] INIT_52 = 256'h0,
    parameter [255:0] INIT_53 = 256'h0,
    parameter [255:0] INIT_54 = 256'h0,
    parameter [255:0] INIT_55 = 256'h0,
    parameter [255:0] INIT_56 = 256'h0,
    parameter [255:0] INIT_57 = 256'h0,
    parameter [255:0] INIT_58 = 256'h0,
    parameter [255:0] INIT_59 = 256'h0,
    parameter [255:0] INIT_5A = 256'h0,
    parameter [255:0] INIT_5B = 256'h0,
    parameter [255:0] INIT_5C = 256'h0,
    parameter [255:0] INIT_5D = 256'h0,
    parameter [255:0] INIT_5E = 256'h0,
    parameter [255:0] INIT_5F = 256'h0,
    parameter [255:0] INIT_60 = 256'h0,
    parameter [255:0] INIT_61 = 256'h0,
    parameter [255:0] INIT_62 = 256'h0,
    parameter [255:0] INIT_63 = 256'h0,
    parameter [255:0] INIT_64 = 256'h0,
    parameter [255:0] INIT_65 = 256'h0,
    parameter [255:0] INIT_66 = 256'h0,
    parameter [255:0] INIT_67 = 256'h0,
    parameter [255:0] INIT_68 = 256'h0,
    parameter [255:0] INIT_69 = 256'h0,
    parameter [255:0] INIT_6A = 256'h0,
    parameter [255:0] INIT_6B = 256'h0,
    parameter [255:0] INIT_6C = 256'h0,
    parameter [255:0] INIT_6D = 256'h0,
    parameter [255:0] INIT_6E = 256'h0,
    parameter [255:0] INIT_6F = 256'h0,
    parameter [255:0] INIT_70 = 256'h0,
    parameter [255:0] INIT_71 = 256'h0,
    parameter [255:0] INIT_72 = 256'h0,
    parameter [255:0] INIT_73 = 256'h0,
    parameter [255:0] INIT_74 = 256'h0,
    parameter [255:0] INIT_75 = 256'h0,
    parameter [255:0] INIT_76 = 256'h0,
    parameter [255:0] INIT_77 = 256'h0,
    parameter [255:0] INIT_78 = 256'h0,
    parameter [255:0] INIT_79 = 256'h0,
    parameter [255:0] INIT_7A = 256'h0,
    parameter [255:0] INIT_7B = 256'h0,
    parameter [255:0] INIT_7C = 256'h0,
    parameter [255:0] INIT_7D = 256'h0,
    parameter [255:0] INIT_7E = 256'h0,
    parameter [255:0] INIT_7F = 256'h0,
    parameter [255:0] INITP_00 = 256'h0,
    parameter [255:0] INITP_01 = 256'h0,
    parameter [255:0] INITP_02 = 256'h0,
    parameter [255:0] INITP_03 = 256'h0,
    parameter [255:0] INITP_04 = 256'h0,
    parameter [255:0] INITP_05 = 256'h0,
    parameter [255:0] INITP_06 = 256'h0,
    parameter [255:0] INITP_07 = 256'h0,
    parameter [255:0] INITP_08 = 256'h0,
    parameter [255:0] INITP_09 = 256'h0,
    parameter [255:0] INITP_0A = 256'h0,
    parameter [255:0] INITP_0B = 256'h0,
    parameter [255:0] INITP_0C = 256'h0,
    parameter [255:0] INITP_0D = 256'h0,
    parameter [255:0] INITP_0E = 256'h0,
    parameter [255:0] INITP_0F = 256'h0,
    parameter DUMMY = 0
) (
    output CASCADEOUTA, CASCADEOUTB, output reg [31:0] DOADO, DOBDO, output reg [3:0] DOPADOP, DOPBDOP,
    output [7:0] ECCPARITY, output [8:0] RDADDRECC, output SBITERR, DBITERR,
    input ENARDEN, CLKARDCLK, RSTRAMARSTRAM, RSTREGARSTREG, CASCADEINA, REGCEAREGCE,
    input ENBWREN, CLKBWRCLK, RSTRAMB, RSTREGB, CASCADEINB, REGCEB, INJECTDBITERR, INJECTSBITERR,
    input [15:0] ADDRARDADDR, ADDRBWRADDR, input [31:0] DIADI, DIBDI, input [3:0] DIPADIP, DIPBDIP,
    input [3:0] WEA, input [7:0] WEBWE);
  localparam integer W = READ_WIDTH_A != 0 ? READ_WIDTH_A : READ_WIDTH_B != 0 ? READ_WIDTH_B : WRITE_WIDTH_A != 0 ? WRITE_WIDTH_A : WRITE_WIDTH_B;
  localparam integer DW = W == 36 ? 32 : W == 18 ? 16 : W == 9 ? 8 : W;   // data bits per word
  localparam integer PW = W == 36 ? 4 : W == 18 ? 2 : W == 9 ? 1 : 0;     // parity bits per word
  localparam integer SH = W == 36 ? 5 : W == 18 ? 4 : W == 9 ? 3 : W == 4 ? 2 : W == 2 ? 1 : 0;
  reg [32767:0] mem;
  reg [4095:0]  memp;
  initial begin
    DOADO = 0; DOBDO = 0; DOPADOP = 0; DOPBDOP = 0;
    mem[0 +: 256] = INIT_00;
    mem[256 +: 256] = INIT_01;
    mem[512 +: 256] = INIT_02;
    mem[768 +: 256] = INIT_03;
    mem[1024 +: 256] = INIT_04;
    mem[1280 +: 256] = INIT_05;
    mem[1536 +: 256] = INIT_06;
    mem[1792 +: 256] = INIT_07;
    mem[2048 +: 256] = INIT_08;
    mem[2304 +: 256] = INIT_09;
    mem[2560 +: 256] = INIT_0A;
    mem[2816 +: 256] = INIT_0B;
    mem[3072 +: 256] = INIT_0C;
    mem[3328 +: 256] = INIT_0D;
    mem[3584 +: 256] = INIT_0E;
    mem[3840 +: 256] = INIT_0F;
    mem[4096 +: 256] = INIT_10;
    mem[4352 +: 256] = INIT_11;
    mem[4608 +: 256] = INIT_12;
    mem[4864 +: 256] = INIT_13;
    mem[5120 +: 256] = INIT_14;
    mem[5376 +: 256] = INIT_15;
    mem[5632 +: 256] = INIT_16;
    mem[5888 +: 256] = INIT_17;
    mem[6144 +: 256] = INIT_18;
    mem[6400 +: 256] = INIT_19;
    mem[6656 +: 256] = INIT_1A;
    mem[6912 +: 256] = INIT_1B;
    mem[7168 +: 256] = INIT_1C;
    mem[7424 +: 256] = INIT_1D;
    mem[7680 +: 256] = INIT_1E;
    mem[7936 +: 256] = INIT_1F;
    mem[8192 +: 256] = INIT_20;
    mem[8448 +: 256] = INIT_21;
    mem[8704 +: 256] = INIT_22;
    mem[8960 +: 256] = INIT_23;
    mem[9216 +: 256] = INIT_24;
    mem[9472 +: 256] = INIT_25;
    mem[9728 +: 256] = INIT_26;
    mem[9984 +: 256] = INIT_27;
    mem[10240 +: 256] = INIT_28;
    mem[10496 +: 256] = INIT_29;
    mem[10752 +: 256] = INIT_2A;
    mem[11008 +: 256] = INIT_2B;
    mem[11264 +: 256] = INIT_2C;
    mem[11520 +: 256] = INIT_2D;
    mem[11776 +: 256] = INIT_2E;
    mem[12032 +: 256] = INIT_2F;
    mem[12288 +: 256] = INIT_30;
    mem[12544 +: 256] = INIT_31;
    mem[12800 +: 256] = INIT_32;
    mem[13056 +: 256] = INIT_33;
    mem[13312 +: 256] = INIT_34;
    mem[13568 +: 256] = INIT_35;
    mem[13824 +: 256] = INIT_36;
    mem[14080 +: 256] = INIT_37;
    mem[14336 +: 256] = INIT_38;
    mem[14592 +: 256] = INIT_39;
    mem[14848 +: 256] = INIT_3A;
    mem[15104 +: 256] = INIT_3B;
    mem[15360 +: 256] = INIT_3C;
    mem[15616 +: 256] = INIT_3D;
    mem[15872 +: 256] = INIT_3E;
    mem[16128 +: 256] = INIT_3F;
    mem[16384 +: 256] = INIT_40;
    mem[16640 +: 256] = INIT_41;
    mem[16896 +: 256] = INIT_42;
    mem[17152 +: 256] = INIT_43;
    mem[17408 +: 256] = INIT_44;
    mem[17664 +: 256] = INIT_45;
    mem[17920 +: 256] = INIT_46;
    mem[18176 +: 256] = INIT_47;
    mem[18432 +: 256] = INIT_48;
    mem[18688 +: 256] = INIT_49;
    mem[18944 +: 256] = INIT_4A;
    mem[19200 +: 256] = INIT_4B;
    mem[19456 +: 256] = INIT_4C;
    mem[19712 +: 256] = INIT_4D;
    mem[19968 +: 256] = INIT_4E;
    mem[20224 +: 256] = INIT_4F;
    mem[20480 +: 256] = INIT_50;
    mem[20736 +: 256] = INIT_51;
    mem[20992 +: 256] = INIT_52;
    mem[21248 +: 256] = INIT_53;
    mem[21504 +: 256] = INIT_54;
    mem[21760 +: 256] = INIT_55;
    mem[22016 +: 256] = INIT_56;
    mem[22272 +: 256] = INIT_57;
    mem[22528 +: 256] = INIT_58;
    mem[22784 +: 256] = INIT_59;
    mem[23040 +: 256] = INIT_5A;
    mem[23296 +: 256] = INIT_5B;
    mem[23552 +: 256] = INIT_5C;
    mem[23808 +: 256] = INIT_5D;
    mem[24064 +: 256] = INIT_5E;
    mem[24320 +: 256] = INIT_5F;
    mem[24576 +: 256] = INIT_60;
    mem[24832 +: 256] = INIT_61;
    mem[25088 +: 256] = INIT_62;
    mem[25344 +: 256] = INIT_63;
    mem[25600 +: 256] = INIT_64;
    mem[25856 +: 256] = INIT_65;
    mem[26112 +: 256] = INIT_66;
    mem[26368 +: 256] = INIT_67;
    mem[26624 +: 256] = INIT_68;
    mem[26880 +: 256] = INIT_69;
    mem[27136 +: 256] = INIT_6A;
    mem[27392 +: 256] = INIT_6B;
    mem[27648 +: 256] = INIT_6C;
    mem[27904 +: 256] = INIT_6D;
    mem[28160 +: 256] = INIT_6E;
    mem[28416 +: 256] = INIT_6F;
    mem[28672 +: 256] = INIT_70;
    mem[28928 +: 256] = INIT_71;
    mem[29184 +: 256] = INIT_72;
    mem[29440 +: 256] = INIT_73;
    mem[29696 +: 256] = INIT_74;
    mem[29952 +: 256] = INIT_75;
    mem[30208 +: 256] = INIT_76;
    mem[30464 +: 256] = INIT_77;
    mem[30720 +: 256] = INIT_78;
    mem[30976 +: 256] = INIT_79;
    mem[31232 +: 256] = INIT_7A;
    mem[31488 +: 256] = INIT_7B;
    mem[31744 +: 256] = INIT_7C;
    mem[32000 +: 256] = INIT_7D;
    mem[32256 +: 256] = INIT_7E;
    mem[32512 +: 256] = INIT_7F;
    memp[0 +: 256] = INITP_00;
    memp[256 +: 256] = INITP_01;
    memp[512 +: 256] = INITP_02;
    memp[768 +: 256] = INITP_03;
    memp[1024 +: 256] = INITP_04;
    memp[1280 +: 256] = INITP_05;
    memp[1536 +: 256] = INITP_06;
    memp[1792 +: 256] = INITP_07;
    memp[2048 +: 256] = INITP_08;
    memp[2304 +: 256] = INITP_09;
    memp[2560 +: 256] = INITP_0A;
    memp[2816 +: 256] = INITP_0B;
    memp[3072 +: 256] = INITP_0C;
    memp[3328 +: 256] = INITP_0D;
    memp[3584 +: 256] = INITP_0E;
    memp[3840 +: 256] = INITP_0F;
  end
  wire [14:0] aa = {ADDRARDADDR[14:SH], {SH{1'b0}}};
  wire [14:0] ab = {ADDRBWRADDR[14:SH], {SH{1'b0}}};
  wire        wa = WRITE_WIDTH_A != 0 && |WEA;
  wire        wb = WRITE_WIDTH_B != 0 && |WEBWE[3:0];
  integer i;
  always @(posedge CLKARDCLK) if (ENARDEN) begin
    if (!(wa && WRITE_MODE_A == "NO_CHANGE")) begin
      for (i = 0; i < DW; i = i + 1) DOADO[i] <= (wa && WRITE_MODE_A == "WRITE_FIRST" && WEA[i / 8]) ? DIADI[i] : mem[32'(aa) + i];
      for (i = 0; i < PW; i = i + 1) DOPADOP[i] <= (wa && WRITE_MODE_A == "WRITE_FIRST" && WEA[i]) ? DIPADIP[i] : memp[32'(aa) / 8 + i];
    end
    if (wa) begin
      for (i = 0; i < DW; i = i + 1) if (WEA[i / 8]) mem[32'(aa) + i] <= DIADI[i];
      for (i = 0; i < PW; i = i + 1) if (WEA[i]) memp[32'(aa) / 8 + i] <= DIPADIP[i];
    end
  end
  always @(posedge CLKBWRCLK) if (ENBWREN) begin
    if (!(wb && WRITE_MODE_B == "NO_CHANGE")) begin
      for (i = 0; i < DW; i = i + 1) DOBDO[i] <= (wb && WRITE_MODE_B == "WRITE_FIRST" && WEBWE[i / 8]) ? DIBDI[i] : mem[32'(ab) + i];
      for (i = 0; i < PW; i = i + 1) DOPBDOP[i] <= (wb && WRITE_MODE_B == "WRITE_FIRST" && WEBWE[i]) ? DIPBDIP[i] : memp[32'(ab) / 8 + i];
    end
    if (wb) begin
      for (i = 0; i < DW; i = i + 1) if (WEBWE[i / 8]) mem[32'(ab) + i] <= DIBDI[i];
      for (i = 0; i < PW; i = i + 1) if (WEBWE[i]) memp[32'(ab) / 8 + i] <= DIPBDIP[i];
    end
  end
  assign CASCADEOUTA = 1'b0; assign CASCADEOUTB = 1'b0; assign ECCPARITY = 0; assign RDADDRECC = 0; assign SBITERR = 0; assign DBITERR = 0;
endmodule
