using FixedPointNumbers

include("microcode.jl")

const Fix = Fixed{Int32, 16}
const Fix_frac_bits = 16

int2fix(i::Integer) = Fix(i, 0)
fix2int(x::Fix) = x.i

struct Parameters
	mem_int_bits::Int
	reg_int_bits::Int
	result_int_bits::Int
	frac_bits::Int
end

mutable struct DataPath
	p::Parameters

	result::Fix
	t::Fix
	f1::Fix
	f2::Fix

	positive::Bool # flag stored by some instructions
	overflow::Bool # flag stored by some instructions
	bias::Int # used when C_DITHER is set

	outputs::Vector{Fix}
end
DataPath(p::Parameters) = DataPath(p, 0, 0, 0, 0, true, false, 0, zeros(Fix, 2))

function fix_trunc(x::Fix, int_bits::Int, frac_bits::Int)
	shift = 32 - (Fix_frac_bits + int_bits + 1)
	i::Int32 = x.i << shift
	i >>= shift
	i &= (-1 << (Fix_frac_bits - frac_bits))
	return int2fix(i)
end

mem_trunc(p::Parameters, x::Fix) = fix_trunc(x, p.mem_int_bits, p.frac_bits)
reg_trunc(p::Parameters, x::Fix) = fix_trunc(x, p.reg_int_bits, p.frac_bits)

function get_a(dp::DataPath)
	@assert dp.t == dp.f1 == dp.f2
	return mem_trunc(dp.p, dp.t)
end

fix_round(x, frac_bits) = int2fix(round(Int, x*(1 << frac_bits)) << (Fix_frac_bits - frac_bits))

function madd(p::Parameters, f1::Fix, f2::Fix, t::Fix, bias::Int)
	f1, f2, t = reg_trunc(p, f1), reg_trunc(p, f2), reg_trunc(p, t)
	bias &= (1 << (2*Fix_frac_bits - p.frac_bits)) - 1

	f1i::Int64 = f1.i
	f2i::Int64 = f2.i
	ti::Int64 = t.i

	ti_full = (ti << Fix_frac_bits) + bias
	r = ((f1i*f2i + ti_full) >> Fix_frac_bits)

	return fix_trunc(int2fix(r), p.result_int_bits, p.frac_bits)
end
madd(p::Parameters, f1::Fix, f2::Fix, t::Fix) = madd(p, f1, f2, t, 1 << (2*Fix_frac_bits - (p.frac_bits + 1)))

Base.clamp(p::Parameters, x::Fix) = mem_trunc(p, int2fix(clamp(x.i, -1 << (Fix_frac_bits + p.mem_int_bits), (1 << (Fix_frac_bits + p.mem_int_bits)) - 1)))

# Functions to set result
mem!(  dp::DataPath, x::Fix)       = (dp.result = mem_trunc(dp.p, x))
const!(dp::DataPath, x::Fix)       = (dp.result = reg_trunc(dp.p, x))
madd!( dp::DataPath, dither::Bool) = (dp.result = madd(dp.p, dp.f1, dp.f2, dp.t, dither ? dp.bias : 1 << (2*Fix_frac_bits - (dp.p.frac_bits + 1)) ))
clamp!(dp::DataPath)               = (dp.result = clamp(dp.p, dp.result))
trunc!(dp::DataPath)               = (dp.result = mem_trunc(dp.p, dp.result))

function bit_reverse(x::Integer, num_bits::Integer)
	y = 0
	for k=1:num_bits
		y <<= 1
		y |= x & 1
		x >>= 1
	end
	return y
end

function reg_write!(dp::DataPath, we::Int)
	if (we & SIGN_WE != 0) dp.positive = (dp.f2 >= 0); end
	r = reg_trunc(dp.p, dp.result)
	if (we & T_WE  != 0) dp.t = r; end
	if (we & F1_WE != 0) dp.f1 = r; end
	if (we & F2_WE != 0) dp.f2 = r; end

	if (we & BIAS_WE != 0)
		delta_frac_bits = Fix_frac_bits - dp.p.frac_bits
		bits = fix2int(r) >> delta_frac_bits
		dp.bias = bit_reverse(bits, dp.p.frac_bits) << (2*delta_frac_bits)
	end
end

lfsr16_bit(x::Integer) = xor(x >> 15, x >> 14, x >> 12, x >> 3) & 1

function exec!(dp::DataPath, context::IContext, c::DPControl, mem::Fix)
	# Make sure that these flags are stored in the c.res field for now
	@assert c.reg_we & C_CLAMP == 0

	control = c.res | c.reg_we
	res = control & ((1 << result_sel_bits)-1)

	# Based on original result selector
	result_sel = res < 4 ? res : 0

	const_sel = res
	# TODO: handle res_exp2 here instead
	if control & C_STORED_SIGN != 0
		const_sel = (const_sel & ~1) | (dp.positive ? 0 : 1)
	elseif res == res_lfsr
		x = fix2int(dp.f2) >> (Fix_frac_bits - p.frac_bits)
		const_sel = (const_sel & ~1) | (lfsr16_bit(x) & 1)
	end

	dither = (control & C_DITHER != 0)

	store_overflow = (control & OVERFLOW_WE != 0)
	@assert !(store_overflow && result_sel != res_madd)

	if result_sel == res_mem
		mem!(dp, mem)
	elseif result_sel == res_madd
		madd!(dp, dither)
		if store_overflow; dp.overflow = !(Fix(-1 << p.mem_int_bits) <= dp.result < Fix(1 << p.mem_int_bits)); end
		if (control & C_CLAMP != 0); clamp!(dp); end
	elseif result_sel == res_const
		if     const_sel == res_zero;       const!(dp, Fix(0))
		elseif const_sel == res_maxval;     const!(dp, int2fix((1 << Fix_frac_bits)-1))
		elseif const_sel == res_madd;       const!(dp, Fix(-1)) # paired with res_maxval for clamping and pulse wave
		elseif const_sel == res_one;        const!(dp, Fix(1))
		elseif const_sel == res_m_one;      const!(dp, Fix(-1))
		elseif const_sel == res_two;        const!(dp, Fix(2))
		elseif const_sel == res_m_two;      const!(dp, Fix(-2))
		elseif const_sel == res_lfsr;       const!(dp, Fix(0))
		elseif const_sel == res_eps;        const!(dp, int2fix(1<<(Fix_frac_bits - dp.p.frac_bits)))
		elseif const_sel == res_1_fifth;    const!(dp, fix_round(1/5, dp.p.frac_bits))
		elseif const_sel == res_m_6_fifths; const!(dp, fix_round(-6/5, dp.p.frac_bits))
		elseif const_sel == res_exp2;       const!(dp, context.n <= IC_N_ZERO ? Fix(0) : int2fix(1<<(Fix_frac_bits + context.n)))
		else error(string("Unsupported const_sel = ", const_sel))
		end
	else
		error(string("Unsupported result_sel = ", result_sel))
	end

	if (control & C_TRUNC != 0) trunc!(dp); end

	reg_write!(dp, c.reg_we)

	r = mem_trunc(dp.p, dp.result)
	if (c.reg_we & OUTPUT_WE != 0) dp.outputs[context.n+1] = r; end
	return r
end
exec!(dp::DataPath, c::DPControl) = exec!(dp, c, Fix(0))

function exec!(dp::DataPath, context::IContext, c::CycleControl, imm::Fix, mem::Fix)
	mem_data = c.cn & C_MEM_ADDR != 0 ? mem : imm;
	r = exec!(dp, context, c.cdp, mem_data)
	mem_write_mask = 0
	if (c.cn & C_M_WE != 0) && ((c.cn & C_CONDITIONAL_M_WE == 0) || dp.overflow)
		if (c.cn & C_MEM_ADDR != 0) 
			mem_write_mask = 2
			mem = r
		else
			mem_write_mask = 1
			imm = r
		end
	end
	return (imm, mem, mem_write_mask)
end

function exec!(dp::DataPath, context::IContext, cs::Vector{CycleControl}, imm::Fix, mem::Fix)
	for c in cs
		(imm, mem, mem_write_mask) = exec!(dp, context, c, imm, mem)
	end
	return (imm, mem)
end

exec!(dp::DataPath, context::IContext, c, imm::Fix) = ((imm, mem) = exec!(dp, context, c, imm, Fix(0)); imm)
exec!(dp::DataPath, context::IContext, c) =                        (exec!(dp, context, c, Fix(0), Fix(0)); ())


exec!(dp::DataPath, inst::Instruction, imm::Fix, mem::Fix) = exec!(dp, inst.context, opcode_programs[inst.op], imm, mem)
exec!(dp::DataPath, op::Opcode, imm::Fix, mem::Fix) = exec!(dp, Instruction(op), imm, mem)

exec!(dp::DataPath, i::Union{Instruction, Opcode}, imm::Fix) = ((imm, mem) = exec!(dp, i, imm, Fix(0)); imm)
exec!(dp::DataPath, i::Union{Instruction, Opcode}) =                        (exec!(dp, i, Fix(0), Fix(0)); ())

function sina2(dp::DataPath, x)
	exec!(dp, inst_imm, Fix(x))
	exec!(dp, inst_sina2)
	return get_a(dp)
end

function sina4(dp::DataPath, x)
	exec!(dp, inst_imm, Fix(x))
	exec!(dp, inst_sin)
	return get_a(dp)
end

function eval_inst!(dp::DataPath, inst, a, imm)
	exec!(dp, inst_imm, Fix(a))
	exec!(dp, inst, Fix(imm))
	return get_a(dp)
end
eval_inst!(dp::DataPath, inst, a) = eval_inst!(dp, inst, a, Fix(0))


mutable struct DSP
	dp::DataPath
	code::Vector{Instruction}
	data::Vector{Fix}

	pc::Int
end
DSP(dp, code, data) = DSP(dp, code, data, 0)

function step!(dsp::DSP)
	inst = dsp.code[dsp.pc+1]

	for control in opcode_programs[inst.op]
		# read
		(imm, mem) = (dsp.data[dsp.pc+1], dsp.data[inst.context.addr+1])
		# execute
		(imm, mem, mem_write_mask) = exec!(dsp.dp, inst.context, control, imm, mem)
		# write back
		if     mem_write_mask == 1; dsp.data[dsp.pc+1] = imm;
		elseif mem_write_mask == 2; dsp.data[inst.context.addr+1] = mem;
		end
	end

	dsp.pc += 1
	if dsp.pc == length(dsp.code); dsp.pc = 0; end
end

function run_loop!(dsp::DSP)
	last_pc = -1
	while (dsp.pc > last_pc)
		last_pc = dsp.pc
		step!(dsp)
	end
end

function run_loops!(dsp::DSP, output::Vector{Fix}, n::Int)
	for k=1:n
		run_loop!(dsp)
		push!(output, dsp.dp.outputs[1])
	end
	return output
end
run_loops!(dsp::DSP, n::Int) = run_loops!(dsp::DSP, Fix[], n::Int)

function create_dsp(p::Parameters, program)
	code = Vector{Instruction}(undef, length(program))
	data = zeros(Fix, length(program))
	for (k, (c, d)) in enumerate(program)
		if isa(c, Opcode); c = Instruction(c); end
		code[k] = c;
		data[k] = d;
	end

	return DSP(DataPath(p), code, data)
end
