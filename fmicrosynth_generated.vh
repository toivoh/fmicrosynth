// Generated by julia/codegen.jl -- rerun to regenerate

`ifndef __fmicrosynth_generated_vh
`define __fmicrosynth_generated_vh

`define STATE_BITS 7
`define CONTROL_BITS 19
`define RESULT_SEL_BITS 4

// Result selector codes
`define RES_MAXVAL 5'd0
`define RES_MADD 5'd1
`define RES_MEM 5'd2
`define RES_EXT 5'd3
`define RES_ONE 5'd4
`define RES_M_ONE 5'd5
`define RES_TWO 5'd6
`define RES_M_TWO 5'd7
`define RES_LFSR 5'd8
`define RES_EPS 5'd9
`define RES_1_FIFTH 5'd10
`define RES_M_6_FIFTHS 5'd11
`define RES_ZERO 5'd12
`define RES_EXP2 5'd13

// Control flags
`define T_WE (1 << 4)
`define F1_WE (1 << 5)
`define F2_WE (1 << 6)
`define SIGN_WE (1 << 7)
`define OVERFLOW_WE (1 << 8)
`define OUTPUT_WE (1 << 9)
`define BIAS_WE (1 << 10)
`define C_CLAMP (1 << 11)
`define C_STORED_SIGN (1 << 12)
`define C_TRUNC (1 << 13)
`define C_DITHER (1 << 14)
`define C_M_WE (1 << 15)
`define C_CONDITIONAL_M_WE (1 << 16)
`define C_MEM_ADDR (1 << 17)
`define C_INST_DONE (1 << 18)

// States
`define INST_NOP 0
`define INST_ACC_IMM_TO_MEM 1
`define INST_MACC_TO_MEM 2
`define INST_WADD 3
`define INST_LPFILTER 4
`define INST_PULSE_EXP2 5
`define INST_PULSE 6
`define INST_TRIANGLE 7
`define INST_SINA2 8
`define INST_SIN 9
`define INST_LFSR 10
`define INST_OUTPUT 11
`define INST_OUTPUT_A 12
`define INST_DITHER_UPDATE 13
`define INST_IMM 14
`define INST_ACC_TO_IMM 15
`define INST_ACC_IMM_TO_MEM_2 16
`define INST_ACC_IMM_TO_MEM_3 17
`define INST_ACC_IMM_TO_MEM_4 18
`define INST_MACC_TO_MEM_2 19
`define INST_MACC_TO_MEM_3 20
`define INST_MACC_TO_MEM_4 21
`define INST_MACC_TO_MEM_5 22
`define INST_WADD_2 23
`define INST_WADD_3 24
`define INST_WADD_4 25
`define INST_WADD_5 26
`define INST_WADD_6 27
`define INST_WADD_7 28
`define INST_LPFILTER_2 29
`define INST_LPFILTER_3 30
`define INST_LPFILTER_4 31
`define INST_LPFILTER_5 32
`define INST_LPFILTER_6 33
`define INST_LPFILTER_7 34
`define INST_PULSE_EXP2_2 35
`define INST_PULSE_EXP2_3 36
`define INST_PULSE_EXP2_4 37
`define INST_PULSE_2 38
`define INST_PULSE_3 39
`define INST_PULSE_4 40
`define INST_PULSE_5 41
`define INST_TRIANGLE_2 42
`define INST_TRIANGLE_3 43
`define INST_TRIANGLE_4 44
`define INST_TRIANGLE_5 45
`define INST_SINA2_2 46
`define INST_SINA2_3 47
`define INST_SINA2_4 48
`define INST_SIN_2 49
`define INST_SIN_3 50
`define INST_SIN_4 51
`define INST_SIN_5 52
`define INST_SIN_6 53
`define INST_SIN_7 54
`define INST_SIN_8 55
`define INST_SIN_9 56
`define INST_SIN_10 57
`define INST_SIN_11 58
`define INST_SIN_12 59
`define INST_SIN_13 60
`define INST_LFSR_2 61
`define INST_LFSR_3 62
`define INST_LFSR_4 63
`define INST_OUTPUT_2 64
`define INST_OUTPUT_A_2 65
`define INST_DITHER_UPDATE_2 66
`define INST_DITHER_UPDATE_3 67
`define INST_DITHER_UPDATE_4 68
`define INST_ACC_TO_IMM_2 69
`define INST_ACC_TO_IMM_3 70

`endif // __fmicrosynth_generated_vh
