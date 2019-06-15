`timescale 1ns / 1ps

`include "fmicrosynth_generated.vh"

`define RES_CONST `RES_MAXVAL

`define INST_BITS 16
// Bit field positions in instruction
`define OPCODE_BITPOS 12
`define EXPONENT_BITPOS 8
`define MEM_ADDR_BITPOS 0

`define OPCODE_BITS 4


// TODO: All 3 registers probably don't need the same number of bits
module fms_datapath #(parameter DATA_BITS = 16, REG_BITS = 18) (
        input clk,
        input en, // pause when 0

        input [`INST_BITS-1:0] inst,
        input [`CONTROL_BITS-1:0] control,

        input signed [DATA_BITS-1:0] mem_rdata,

        input signed [DATA_BITS-1:0] ext_result, // pass through to result when en == 0
        output [DATA_BITS-1:0] result,
        output condition,

        output [REG_BITS*5-1:0] registers
    );
    localparam FRAC_BITS = DATA_BITS-1;

    reg signed [REG_BITS-1:0] t, f1, f2;
    reg [FRAC_BITS-1:0] madd_bias_reg = 0;
    reg stored_sign = 0, stored_overflow = 0;

    assign condition = stored_overflow;

    wire [REG_BITS-1:0] madd_bias_reg_bits = madd_bias_reg;  
    assign registers = {stored_overflow, stored_sign, madd_bias_reg_bits, f2, f1, t};

    wire clamp_en = (control & `C_CLAMP) != 0;
    wire [3:0] exponent = inst[`EXPONENT_BITPOS +: 4];

    // Multiply-adder
    // --------------
    // TODO: We should never need quite this many bits to represent the madd result?
    localparam MADD_BITS = REG_BITS*2-1 - FRAC_BITS + 1;

    wire [FRAC_BITS-1:0] madd_bias = (control & `C_DITHER) ? madd_bias_reg : 1 << (FRAC_BITS-1);
    wire signed [REG_BITS+FRAC_BITS-1:0] t_full = {t, madd_bias};
    wire signed [REG_BITS*2-1:0] madd_result_full = t_full + f1*f2;
    wire signed [MADD_BITS-1:0] madd_result = madd_result_full >>> FRAC_BITS;

    wire overflow = madd_result[MADD_BITS-1:DATA_BITS] != {(MADD_BITS-DATA_BITS){madd_result[DATA_BITS-1]}};
    wire clamp_active = overflow && clamp_en;

    // Constant mux
    // ------------
    wire [`RESULT_SEL_BITS-1:0] const_sel = control[0 +: `RESULT_SEL_BITS];
    // Use exponent to select constant?
    wire use_exp2 = (const_sel == `RES_EXP2);
    wire [4:0] _const_sel_1 = {use_exp2, use_exp2 ? exponent : const_sel[3:0]};
    // Use clamping/stored sign to select lowest bit?
    wire use_stored_sign = (control & `C_STORED_SIGN) != 0;
    (* keep = "true" *) wire [4:0] _const_sel;
    assign _const_sel[4:1] = _const_sel_1[4:1];

    wire use_lfsr = (const_sel == `RES_LFSR);
    wire lfsr_bit = use_lfsr & (f2[15] ^ f2[14] ^ f2[12] ^ f2[3]); 

    assign _const_sel[0] = clamp_active ? madd_result[MADD_BITS-1] : (use_stored_sign ? stored_sign : _const_sel_1[0] | lfsr_bit);

    localparam ONE_FIFTH = ((1 << FRAC_BITS)*2 + 5) / 10;
    reg signed [REG_BITS-1:0] constant;
    always @* begin
        case (_const_sel)
            `RES_MAXVAL:     constant = (1 << (DATA_BITS-1)) - 1;
            `RES_MADD:       constant = -1 << (DATA_BITS-1);
            `RES_ZERO:       constant =  0;
            `RES_ONE:        constant =  1 << FRAC_BITS;
            `RES_M_ONE:      constant = -1 << FRAC_BITS;
            `RES_TWO:        constant =  2 << FRAC_BITS;
            `RES_M_TWO:      constant = -2 << FRAC_BITS;
            `RES_LFSR:       constant =  0;
            `RES_EPS:        constant =  1;
            `RES_1_FIFTH:    constant =  ONE_FIFTH;
            `RES_M_6_FIFTHS: constant = -((1 << FRAC_BITS) + ONE_FIFTH);
            5'd16:           constant = 0; // 0 for `RES_EXP2 when exponent is zero
            default:         constant = (1 << (2 + FRAC_BITS - 15)) << (_const_sel & 15); // for `RES_EXP2 : 2^-12, 2^-11, ..., 1, 2, -4
        endcase
    end

    // Result mux
    // ----------
    wire use_trunc = (control & `C_TRUNC) != 0;

    wire [1:0] result_sel = control[`RESULT_SEL_BITS-1:2] == 0 ? control[1:0] : `RES_CONST;
    localparam [1:0] RS_CONST = `RES_CONST;
    localparam [1:0] RS_MADD  = `RES_MADD;
    localparam [1:0] RS_MEM   = `RES_MEM;
    localparam [1:0] RS_EXT   = `RES_EXT;

    wire [1:0] _result_sel_1 = clamp_active ? RS_CONST : result_sel;
    (* keep = "true" *) wire [1:0] _result_sel = en ? _result_sel_1 : RS_EXT;
    reg [REG_BITS-1:0] result1;
    // Should synthesize to one 6-LUT per bit
    always @* begin
        case (_result_sel)
            RS_CONST: result1 = constant;
            RS_MADD:  result1 = use_trunc ? $signed(madd_result[DATA_BITS-1:0]) : madd_result;
            RS_MEM:   result1 = mem_rdata;
            RS_EXT:   result1 = ext_result;
        endcase
    end
    assign result = result1;

    // Bit reverse for madd_bias
    // -------------------------
    wire [FRAC_BITS-1:0] madd_bias_in;
    generate
        genvar k;
        for (k = 0; k < FRAC_BITS; k = k + 1) begin : reverse
            assign madd_bias_in[FRAC_BITS-1 - k] = result[k];
        end
    endgenerate

    // State update
    // ------------
    always @(posedge clk) if (en) begin
        // Update state
        if (control & `T_WE)  t  <= result1;
        if (control & `F1_WE) f1 <= result1;
        if (control & `F2_WE) f2 <= result1;
        if (control & `SIGN_WE) stored_sign <= f2[REG_BITS-1];
        if (control & `OVERFLOW_WE) stored_overflow <= overflow;
        if (control & `BIAS_WE) madd_bias_reg <= madd_bias_in;
    end
endmodule

module fms_controller (
        input clk,
        input reset,
        input en,

        input [`CONTROL_BITS-1:0] control,
        input [`INST_BITS-1:0] inst_in,
        input [`STATE_BITS-1:0] next_state,

        output reg [`INST_BITS-1:0] inst,
        output reg [`STATE_BITS-1:0] state
    );
    initial state = `INST_NOP;

    // When one, all instructions will be replaced by nops (until set to zero by an enable instruction)
    reg disabled = 0;

    wire inst_done = (control & `C_INST_DONE) != 0;
    wire [`OPCODE_BITS-1:0] opcode_in = inst_in[`OPCODE_BITPOS +: `OPCODE_BITS];
    wire [3:0] exp_in = inst_in[`EXPONENT_BITPOS +: 4];

    always @(posedge clk) begin
        if (reset) begin
            state <= `INST_NOP;
            disabled <= 0;
        end else if (en) begin
            if (inst_done) begin
                inst <= inst_in;
                if (disabled) state <= `INST_NOP;
                else          state <= opcode_in;

                // Recognize enable/disable instructions; update disabled
                if (opcode_in == `INST_NOP && exp_in[1] == 1) disabled <= exp_in[0];
            end 
            else state <= next_state;
        end
    end 
endmodule

module fms_memory #(parameter ADDR_BITS=6, DATA_BITS=16) (
        input clk,

        input [ADDR_BITS-1:0] addr,
        input we,
        input [DATA_BITS-1:0] wdata,

        output [DATA_BITS-1:0] rdata
    );
    (* ram_style = "distributed" *) reg [DATA_BITS-1:0] mem[0:2**ADDR_BITS-1];

    assign rdata = mem[addr];
    always @(posedge clk) if (we) mem[addr] = wdata;
endmodule

module fms_address_generator #(parameter ADDR_BITS=6) (
        input clk,
        input en,
        input reset,

        input [ADDR_BITS-1:0] ext_addr,
        input [`CONTROL_BITS-1:0] control,
        input [`INST_BITS-1:0] inst,
        input [ADDR_BITS-1:0] initial_pc,

        output [ADDR_BITS-1:0] code_addr, data_addr,

        output reg [ADDR_BITS-1:0] pc, inst_pc
    );
    initial begin
        pc = 0;
        inst_pc = 0; // pc of current instruction
    end

    wire inst_done = (control & `C_INST_DONE) != 0;
    wire use_mem_addr = (control & `C_MEM_ADDR) != 0;
    wire [ADDR_BITS-1:0] mem_addr = inst[`MEM_ADDR_BITPOS +: ADDR_BITS];

    wire [ADDR_BITS-1:0] data_addr1 = use_mem_addr ? mem_addr : inst_pc;
    assign data_addr = en ? data_addr1 : ext_addr;
    assign code_addr = en ? pc : ext_addr;

    always @(posedge clk) begin
        if (reset) begin
            pc <= initial_pc;
        end else if (en) begin
            if (inst_done) begin
                inst_pc <= pc;
                pc <= pc + 1;
            end
        end
    end
endmodule

module fmicrosynth #(parameter ADDR_BITS = 6, DATA_BITS = 16, REG_BITS = 18) (
        input clk,
        input reset,

        // read/write address
        input [ADDR_BITS-1:0] mem_addr,
        // memory read interface
        input mem_re,
        output [`INST_BITS+DATA_BITS-1:0] mem_rd,
        // memory write interface
        input [3:0] mem_bwe, // byte write enables
        input [`INST_BITS+DATA_BITS-1:0] mem_wd,

        // Raise when sample_l, sample_r have been read, to start computing the next sample
        input trigger,

        output reg signed [DATA_BITS-1:0] sample_l, sample_r, // output samples
        output reg running
    );
    localparam LOW_DATA_BITS = 8;
    localparam HIGH_DATA_BITS = DATA_BITS - LOW_DATA_BITS; 
    localparam LOW_CODE_BITS = 8;
    localparam HIGH_CODE_BITS = `INST_BITS - LOW_CODE_BITS; 

    initial begin
        sample_l = 0;
        sample_r = 0;
        running = 0;
    end

    wire [DATA_BITS-1:0] mem_rdata;
    wire [`INST_BITS-1:0] mem_rcode;
    assign mem_rd = {mem_rcode, mem_rdata};

    wire [1:0] mem_data_bwe, mem_code_bwe;
    assign {mem_code_bwe, mem_data_bwe} = mem_bwe;

    wire [DATA_BITS-1:0] mem_wdata;
    wire [`INST_BITS-1:0] mem_wcode;
    assign {mem_wcode, mem_wdata} = mem_wd;

    wire ext_access = mem_re || |mem_data_bwe || |mem_code_bwe;
    wire en = !ext_access && running && !reset;

    wire condition;

    wire [`INST_BITS-1:0] inst;
    wire [`CONTROL_BITS-1:0] control;

    wire [DATA_BITS-1:0] result;
    wire [ADDR_BITS-1:0] mem_data_addr, mem_code_addr;

    wire result_we_enabled = (control & `C_CONDITIONAL_M_WE) == 0 || condition;
    wire result_we = ((control & `C_M_WE) != 0) && result_we_enabled;
    wire [1:0] data_we = en ? (result_we ? 3 : 0) : mem_data_bwe;
    wire [1:0] code_we = en ? 0 : mem_code_bwe;

    wire [`STATE_BITS-1:0] state, next_state;

    wire [ADDR_BITS-1:0] pc; 
    wire [ADDR_BITS-1:0] initial_pc = 0; 

    fms_datapath #(.DATA_BITS(DATA_BITS), .REG_BITS(REG_BITS)) datapath(
        .clk(clk), .en(en),
        .inst(inst), .control(control),
        .mem_rdata(mem_rdata),
        .ext_result(mem_wdata),
        .result(result), .condition(condition)
    );    

    fms_controller controller(
        .clk(clk), .en(en), .reset(reset),
        .control(control), .inst_in(mem_rcode), .next_state(next_state),
        .inst(inst), .state(state)
    );

    fms_next_state_function next_state_function(.state(state), .next_state(next_state));
    fms_control_function control_function(.state(state), .control(control));

    fms_memory #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(LOW_DATA_BITS)) memory_data_l (
        .clk(clk),
        .addr(mem_data_addr),
        .we(data_we[0]),
        .wdata(result[0 +: LOW_DATA_BITS]),
        .rdata(mem_rdata[0 +: LOW_DATA_BITS])
    );
    fms_memory #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(HIGH_DATA_BITS)) memory_data_h (
        .clk(clk),
        .addr(mem_data_addr),
        .we(data_we[1]),
        .wdata(result[LOW_DATA_BITS +: HIGH_DATA_BITS]),
        .rdata(mem_rdata[LOW_DATA_BITS +: HIGH_DATA_BITS])
    );

    fms_memory #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(LOW_CODE_BITS)) memory_code_l (
        .clk(clk),
        .addr(mem_code_addr),
        .we(code_we[0]),
        .wdata(mem_wcode[0 +: LOW_CODE_BITS]),
        .rdata(mem_rcode[0 +: LOW_CODE_BITS])
    );
    fms_memory #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(HIGH_CODE_BITS)) memory_code_h (
        .clk(clk),
        .addr(mem_code_addr),
        .we(code_we[1]),
        .wdata(mem_wcode[LOW_CODE_BITS +: HIGH_CODE_BITS]),
        .rdata(mem_rcode[LOW_CODE_BITS +: HIGH_CODE_BITS])
    );

    fms_address_generator #(.ADDR_BITS(ADDR_BITS)) address_generator (
        .clk(clk), .en(en), .reset(reset),
        .ext_addr(mem_addr), .control(control), .inst(inst), .initial_pc(initial_pc),

        .code_addr(mem_code_addr), .data_addr(mem_data_addr),
        .pc(pc)
    );

    wire inst_done = (control & `C_INST_DONE) != 0;    
    wire output_we = (control & `OUTPUT_WE) != 0;
    wire output_index = inst[`EXPONENT_BITPOS];
    always @(posedge clk) begin
        if (trigger || reset) running <= 1;
        else if (en && inst_done && pc == initial_pc) running <= 0;

        if (en && output_we) begin
            if (output_index == 0) sample_l <= result;
            if (output_index == 1) sample_r <= result;
        end
    end
endmodule
