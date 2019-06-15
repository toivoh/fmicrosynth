include("meta.jl")

#@enum Result res_mem res_madd res_madd_clamp res_zero res_one res_m_one res_two res_1_fifth res_m_6_fifths res_exp2
@constants result_selections begin
	res_maxval # 0
	res_madd   # 1
	res_mem    # 2
	res_ext    # 3
	res_one    # even
	res_m_one  # odd
	res_two    # even
	res_m_two  # odd
	res_lfsr   # even
	res_eps    # odd
	res_1_fifth
	res_m_6_fifths
	res_zero
	res_exp2
end

const res_const = res_maxval

const const_sel_bits = 5
const result_sel_bits = 4
@flags control_flags 4 begin
# Data path control flags
	# register write enable bits
	T_WE
	F1_WE
	F2_WE
	SIGN_WE   # store sign(f2) into dp.positive
	OVERFLOW_WE # store overflow flag from madd result
	OUTPUT_WE # should probably not be handled by data path
	BIAS_WE
	# other control flags
	C_CLAMP
	C_STORED_SIGN
	C_TRUNC
	C_DITHER

# Non-data path control flags
	C_M_WE
	C_CONDITIONAL_M_WE
	C_MEM_ADDR
	C_INST_DONE
end

const res_madd_clamp = res_madd | C_CLAMP;
const res_stored_sign = res_one | C_STORED_SIGN;

const A_WE = T_WE | F1_WE | F2_WE | C_TRUNC

const MEM_READ = C_MEM_ADDR
const IMM_WE = C_M_WE
const MEM_WE = C_M_WE | C_MEM_ADDR

struct DPControl
	reg_we::Int
	res::Int
end
DPControl(reg_we, res) = DPControl(reg_we, res, 0)

const IC_N_ZERO = -13  # When n == IC_N_ZERO in IContext, the result is scale = 0

struct IContext
	addr::Int
	n::Int
end
IContext(addr) = IContext(addr, 0)
IContext() = IContext(0)

struct CycleControl
	cdp::DPControl
	cn::Int
end

control(flags::Int, res::Int) = CycleControl(DPControl(flags, res), flags)
get_res(c::Int) = c & ((1 << result_sel_bits) - 1)
get_flags(c::Int) = c & (-1 << result_sel_bits)

get_bits(c::CycleControl) = c.cdp.res | c.cn
get_res(c::CycleControl) = get_res(c.cdp.res)
get_flags(c::CycleControl) = get_flags(get_bits(c))

@enum Opcode begin
	inst_nop

	inst_acc_imm_to_mem
	inst_macc_to_mem
	inst_wadd
	inst_lpfilter

	inst_pulse_exp2
	inst_pulse
	inst_triangle
	inst_sina2
	inst_sin

	inst_lfsr

	inst_output
	inst_output_a
	inst_dither_update

	inst_imm
	inst_acc_to_imm
end

struct Instruction
	op::Opcode
	context::IContext
end
Instruction(op::Opcode) = Instruction(op, IContext())


const microcode = [
	inst_nop => [control(0, res_mem)],
	inst_imm => [control(A_WE, res_mem)], # a = imm
	inst_acc_to_imm => [ # a = (imm += 2^-n*a + dither)
		control(F1_WE, res_exp2),
		control(T_WE,  res_mem),
		control(A_WE | IMM_WE | OVERFLOW_WE | C_DITHER, res_madd)
	],
	inst_acc_imm_to_mem => [ # a = (mem += 2^-n*imm + dither)
		control(F1_WE, res_exp2),
		control(F2_WE, res_mem),
		control(T_WE | MEM_READ, res_mem),
		control(A_WE | MEM_WE | OVERFLOW_WE | C_DITHER, res_madd)
	],
	inst_wadd => [ # a = 4^-n*(imm*a) + mem (n can be < 0)
		# f2 = imm*a
		control(T_WE, res_zero),
		control(F1_WE, res_mem),
		control(F2_WE, res_madd),
		# f2 = 2^-n*f2
		control(F1_WE, res_exp2),
		control(F2_WE, res_madd),
		# a = 2^-n*f2 + mem
		control(T_WE | MEM_READ, res_mem),
		control(A_WE, res_madd)
	],
	inst_macc_to_mem => [ # mem = clamp(imm*a + mem) -- keeps value of a!
		control(F1_WE, res_mem),
		control(T_WE | MEM_READ, res_mem),
		control(MEM_WE, res_madd_clamp),
		control(F1_WE, res_one), # restore a from f2...
		control(T_WE, res_zero), #
		control(A_WE, res_madd)  #
	],
	inst_lpfilter =>  [ # a = mem = clamp(mem + 2^-n*(imm - mem) + dither)
		# f2 = imm-mem
		control(T_WE, res_mem),
		control(F1_WE, res_m_one),
		control(F2_WE | MEM_READ, res_mem),
		control(F2_WE, res_madd_clamp),
		# mem += 2^-n*f2 + dither (clamp)
		control(T_WE | MEM_READ, res_mem),
		control(F1_WE, res_exp2),
		control(A_WE | MEM_WE, res_madd_clamp | C_DITHER)
	],
	inst_sina2 => [ # a = -sina2(a)
		# a = 2a + 1/2
		control(F1_WE | SIGN_WE, res_two),
		control(T_WE, res_one),
		control(F1_WE | F2_WE | C_TRUNC, res_madd),
		# a = a*a - 1
		control(T_WE, res_m_one),
		control(F2_WE, res_madd),
		# a *= sign(a_in)
		control(F1_WE, res_stored_sign),
		control(T_WE, res_zero),
		control(A_WE, res_madd_clamp),
	],
	inst_sin => [ # a = sina4(a)
		# a = 2a + 1/2
		control(F1_WE | SIGN_WE, res_two),
		control(T_WE, res_one),
		control(F1_WE | F2_WE | C_TRUNC, res_madd),
		# f1 = a*a
		control(T_WE, res_zero),
		control(F1_WE, res_madd),
		# f2 = -6/5 + 1/5*f1
		control(T_WE, res_m_6_fifths),
		control(F2_WE, res_1_fifth),
		control(F2_WE, res_madd),
		# a = M + f1*f2
		control(T_WE, res_one),
		control(F2_WE, res_madd),
		# a *= sign(a_in)
		control(F1_WE, res_stored_sign),
		control(T_WE, res_zero),
		control(A_WE, res_madd_clamp),
	],
	inst_output => [ # output imm; a = imm = 0
		control(OUTPUT_WE, res_mem),
		control(A_WE | IMM_WE, res_zero)
	],
	inst_dither_update => [ # bias = bit_reverse(imm); a = (imm += epsilon)
		control(T_WE | BIAS_WE, res_mem),
		control(F1_WE, res_one),
		control(F2_WE, res_eps),
		control(A_WE | IMM_WE, res_madd)
	],
	inst_output_a => [ # output a
		control(F1_WE | F2_WE, res_zero),
		control(A_WE | OUTPUT_WE, res_madd)
	],
	inst_pulse => [ # a = a >= imm ? maxval : minval
		control(F1_WE, res_m_one),
		control(F2_WE, res_mem),
		control(F2_WE, res_madd), # f2 = a - imm
		control(SIGN_WE, res_zero), # s = sign(a - imm), TODO: Merge with previous cycle when sign_we reads from result! 
		control(A_WE, res_maxval | C_STORED_SIGN)
	],
	inst_pulse_exp2 => [ # a = a >= -1 + 2^-n ? maxval : minval
		# Prepare
		control(F1_WE | F2_WE, res_one),
		control(T_WE, res_madd),
		# Same as inst_pulse except f2 = 2^-n instead of f2 = imm
		# TODO: Merge with inst_pulse when 2^-n can represent imm
		control(F1_WE, res_m_one),
		control(F2_WE, res_exp2),
		control(F2_WE, res_madd), # f2 = a - imm
		control(SIGN_WE, res_zero), # s = sign(a - imm), TODO: Merge with previous cycle when sign_we reads from result! 
		control(A_WE, res_maxval | C_STORED_SIGN)
	],
	inst_triangle => [ # a = triangle(a)
		# a += 2^-n -- use to get a += 0.5
		control(F1_WE, res_one),
		control(F2_WE, res_exp2),
		control(A_WE, res_madd | C_TRUNC),

		control(T_WE | SIGN_WE, res_m_one),
		control(F1_WE, res_two | C_STORED_SIGN),
		control(A_WE, res_madd_clamp)
	],
	inst_lfsr => [ # a = imm = lfsr(a)
		control(F1_WE, res_two),
		control(F2_WE, res_mem),
		control(T_WE, res_lfsr),
		control(A_WE | IMM_WE | C_CONDITIONAL_M_WE, res_madd)
	],
]
const opcode_programs = Dict(microcode)


const instructions = [
	"nop"            => Instruction(inst_nop,            IContext(0,  IC_N_ZERO)),

	"enable"         => Instruction(inst_nop,            IContext(0,  IC_N_ZERO+2)),
	"disable"        => Instruction(inst_nop,            IContext(0,  IC_N_ZERO+3)),

	"phase_update"   => Instruction(inst_acc_imm_to_mem, IContext(0,  IC_N_ZERO)),
	"contribute"     => Instruction(inst_macc_to_mem,    IContext(0,  IC_N_ZERO)),
	"madd_scale2"    => Instruction(inst_wadd,           IContext(0,  IC_N_ZERO)),
	"approach"       => Instruction(inst_lpfilter,       IContext(0,  IC_N_ZERO)),

	"square"         => Instruction(inst_pulse_exp2,     IContext(0,  0)),
	"pulse"          => Instruction(inst_pulse_exp2,     IContext(0,  IC_N_ZERO)),
	"pulse_imm"      => Instruction(inst_pulse,          IContext(0,  IC_N_ZERO)),
	"sawtooth"       => Instruction(inst_nop,            IContext(0,  IC_N_ZERO)), # synonym for nop
	"triangle"       => Instruction(inst_triangle,       IContext(0, -1)),
	"sina2"          => Instruction(inst_sina2,          IContext(0,  IC_N_ZERO)),
	"sin"            => Instruction(inst_sin,            IContext(0,  IC_N_ZERO)),

	"noise_update"   => Instruction(inst_lfsr,           IContext(0,  IC_N_ZERO)),

	"output"         => Instruction(inst_output,         IContext(0,  IC_N_ZERO)),
	"output_left"    => Instruction(inst_output,         IContext(0,  IC_N_ZERO)),
	"output_right"   => Instruction(inst_output,         IContext(0,  IC_N_ZERO+1)),
	"output_a"       => Instruction(inst_output_a,       IContext(0,  IC_N_ZERO)),
	"output_a_left"  => Instruction(inst_output_a,       IContext(0,  IC_N_ZERO)),
	"output_a_right" => Instruction(inst_output_a,       IContext(0,  IC_N_ZERO+1)),

	"loop_update"    => Instruction(inst_dither_update,  IContext(0,  IC_N_ZERO)),
]
