module TestDSP
using Test
include("simulator.jl")

p = Parameters(0,2,5,15)

const delta_frac_bits = Fix_frac_bits - 15
const maxval = int2fix(((1<<15)-1)*(1 << delta_frac_bits))
const minval = Fix(-1)

triangle(x) = abs.(mod.(x .+ 1.5,2).-1)*2 .- 1

function test_waveform(f, inst, imm; tol = 0)
	t = int2fix.((-32768:32767)*(1 << delta_frac_bits))
	dp = DataPath(p)

	y = eval_inst!.((dp,),(inst,), t, imm)
	y_expected = f.(t)
	if tol == 0
		@test y == y_expected
	else
		@test maximum(abs.(y-y_expected)) <= tol
	end
end
test_waveform(f, inst) = test_waveform(f, inst, Fix(0))

function test_waveforms()
	triangle_i = Instruction(inst_triangle, IContext(0,-1))
	test_waveform(t->(min.(maxval, triangle(t))), triangle_i)

	test_waveform(t->(t >= 0 ? maxval : minval), inst_pulse, Fix(0))
	t0 = mem_trunc(p, Fix(0.73981))
	test_waveform(t->(t >= t0 ? maxval : minval), inst_pulse, t0)

	for k=0:12
		inst = Instruction(inst_pulse_exp2, IContext(0,-k))
		t0 = Fix(-1 + 1/2^k)
		test_waveform(t->(t >= t0 ? maxval : minval), inst)
	end

	test_waveform(t->sin(pi*t), inst_sin, Fix(0); tol = 6.3e-3)
end

function test_lfsr()
	initial = mem_trunc(p, int2fix(1<<delta_frac_bits))
	program = [
		(inst_imm,Fix(0.5)),
		(Instruction(inst_acc_to_imm, IContext(0,2)), Fix(0)), # force overflow every loop with imm += 2^2 * 0.5
		(Instruction(inst_lfsr, IContext(0)), initial),
		(inst_output_a,0)
	]
	dsp = create_dsp(p, program)
	y = run_loops!(dsp, 65535)
	@test dsp.data[3] == initial

	program = [
		(inst_imm,Fix(0.5)),
		(Instruction(inst_acc_to_imm, IContext(0)), Fix(0)), # only overflow every 4th loop
		(Instruction(inst_lfsr, IContext(0)), initial),
		(inst_output_a,0)
	]
	dsp = create_dsp(p, program)
	y2 = run_loops!(dsp, 65535*4)
	@test dsp.data[3] == initial

	x = 1
	y_expected = zeros(Fix, 65535)
	y2_expected = zeros(Fix, 65535*4)
	for k=1:65536
		x = ((x << 1) | lfsr16_bit(x)) & 65535
		xf = int2fix((((x .+ 32768) .& 65535) .- 32768) << delta_frac_bits)
		if (k < 65536)
			y_expected[k] = xf

			y2_expected[(k-1)*4+1] = xf
			y2_expected[(k-1)*4+2] = xf
		end
		if (k > 1)
			y2_expected[(k-1)*4-1] = xf
			y2_expected[(k-1)*4-0] = xf
		end
	end
	@test y == y_expected
	@test y2 == y2_expected
end

function test_bias()
	dp = DataPath(p)

	imm = Fix(0)
	biases = [0, 0x10000, 0x08000, 0x18000]
	for k=1:4
		imm = exec!(dp, inst_dither_update, imm)
		@test fix2int(imm) == 2*k
		@test dp.bias == biases[k]
		@test madd(p, Fix(2^-15), Fix((0x1fffc - dp.bias)*2^-17), Fix(0), dp.bias) == 0
		@test madd(p, Fix(2^-15), Fix((0x20000 - dp.bias)*2^-17), Fix(0), dp.bias) == Fix(2^-15)
	end
end

function test_dither_acc()
	# Test that dithering can give us freq_exp bits of extra frequency accuracy over a period of freq_exp cycles
	freq = reg_trunc(p, Fix(1/7))
	for freq_exp=1:12
		for k=1:2
			program = [
				(inst_imm, freq),
				(Instruction(inst_acc_to_imm, IContext(1, -freq_exp)), Fix(0)),
				(inst_output_a, Fix(0)),
			]
			if (k == 2)
				push!(program, (inst_dither_update, Fix(2^-15)))
			end
			dsp = create_dsp(p, program)
			y = run_loops!(dsp, 2^freq_exp)
			if (k == 1)
				@test y[end] != freq
			else
				@test y[end] == freq
			end
		end
	end
end

test_waveforms()
test_lfsr()

@test bit_reverse(1+8, 4) == 8+1
@test bit_reverse(1+8, 6) == 32+4
test_bias()
test_dither_acc()

end
