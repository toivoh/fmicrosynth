using WAV
using Dierckx

const A4 = 440
const C4 = 440/2^(9/12)
const C5 = C4*2
const C6 = C4*4
const C3 = C4/2
const C2 = C4/4
const C1 = C4/8

fs = 48000
p = Parameters(0,2,5,15)

maxval = 1-1/32768

square_i = Instruction(inst_pulse_exp2, IContext(0, 0))
triangle_i = Instruction(inst_triangle, IContext(0,-1))

f_env = 60
#f_env = 480
#f_env = 1000
n_env = div(fs, f_env)
h_env = 1/f_env

range_clamp(x) = clamp.(x, -1, maxval)

function f_to_freq_exp(f)
	freq = 2*f/fs
	e = 0
	if freq > 0
		while (freq > 1)
			freq /= 2
			e += 1
		end
		while (freq < 0.5)
			freq *= 2
			e -= 1
		end
	end
	return (Fix(freq), e)
end

function fm_program(fc, fm; gain_m_exp4=0, m_inst = inst_sin, c_inst = inst_sin)
	freq_c, exp_c = f_to_freq_exp(fc)
	freq_m, exp_m = f_to_freq_exp(fm)

	gain_m = gain_c = Fix(0.0)

	phase_c_addr, phase_m_addr = 4, 2
	gain_c_addr, gain_m_addr = 5, 3
	mix_addr = 6
	program = [
		(Instruction(inst_acc_imm_to_mem, IContext(phase_c_addr, exp_c)), freq_c),
		(Instruction(inst_acc_imm_to_mem, IContext(phase_m_addr, exp_m)), freq_m),
		(m_inst, Fix(0)), # phase_m
		(Instruction(inst_wadd, IContext(phase_c_addr, gain_m_exp4)), gain_m),
		(c_inst, Fix(0)), # phase_c
		(Instruction(inst_macc_to_mem, IContext(mix_addr)), gain_c),

		(inst_output, Fix(0)),
		(inst_dither_update, Fix(2^-15))
	]

	d = Dict(:gain_c => gain_c_addr, :gain_m => gain_m_addr)
	return (program, d)
end

function fm_program_lp(fc, fm, lp_exp; gain_m_exp4=0, m_inst = inst_sin, c_inst = inst_sin)
	freq_c, exp_c = f_to_freq_exp(fc)
	freq_m, exp_m = f_to_freq_exp(fm)

	gain_m = gain_c = Fix(0.0)

	phase_c_addr, phase_m_addr = 6, 4
	gain_c_addr, gain_m_addr = 0, 1
	filt_gain_c_addr, filt_gain_m_addr = 7, 5
	mix_addr = 8
	program = [
		(Instruction(inst_lpfilter, IContext(filt_gain_c_addr, lp_exp)), gain_c), # gain_c parameter (unfiltered)
		(Instruction(inst_lpfilter, IContext(filt_gain_m_addr, lp_exp)), gain_m), # gain_m parameter (unfiltered)
		(Instruction(inst_acc_imm_to_mem, IContext(phase_c_addr, exp_c)), freq_c),
		(Instruction(inst_acc_imm_to_mem, IContext(phase_m_addr, exp_m)), freq_m),
		(m_inst, Fix(0)), # phase_m
		(Instruction(inst_wadd, IContext(phase_c_addr, gain_m_exp4)), gain_m),
		(c_inst, Fix(0)), # phase_c
		(Instruction(inst_macc_to_mem, IContext(mix_addr)), gain_c),

		(inst_output, Fix(0)),
		(inst_dither_update, Fix(2^-15))
	]

	d = Dict(:gain_c => gain_c_addr, :gain_m => gain_m_addr)
	return (program, d)
end

function fm_and_noise_program(fc, fm, fn; gain_m_exp4=0, m_inst = inst_sin, c_inst = inst_sin)
	freq_c, exp_c = f_to_freq_exp(fc)
	freq_m, exp_m = f_to_freq_exp(fm)
	freq_n, exp_n = f_to_freq_exp(fn)

	gain_m = gain_c = gain_n = Fix(0.0)

	phase_c_addr, phase_m_addr, phase_n_addr = 4, 2, 7
	gain_c_addr, gain_m_addr, gain_n_addr = 5, 3, 9

	mix_addr = 10
	program = [
		(Instruction(inst_acc_imm_to_mem, IContext(phase_c_addr, exp_c)), freq_c),
		(Instruction(inst_acc_imm_to_mem, IContext(phase_m_addr, exp_m)), freq_m),
		(m_inst, Fix(0)), # phase_m
		(Instruction(inst_wadd, IContext(phase_c_addr, gain_m_exp4)), gain_m),
		(c_inst, Fix(0)), # phase_c
		(Instruction(inst_macc_to_mem, IContext(mix_addr)), gain_c),

		(Instruction(inst_acc_imm_to_mem, IContext(phase_n_addr, exp_n)), freq_n),
		(inst_nop, 0), # phase_n
		(inst_lfsr, -1),
		(Instruction(inst_macc_to_mem, IContext(mix_addr)), gain_n),

		(inst_output, Fix(0)),
		(inst_dither_update, Fix(2^-15))
	]

	d = Dict(:gain_c => gain_c_addr, :gain_m => gain_m_addr, :gain_n => gain_n_addr)
	return (program, d)
end

function synthesize!(filename, program, t, env)
	dsp = create_dsp(p, program)
	s = Fix[]
	for k=1:length(t)
		for (addr, data) in env
			dsp.data[addr+1] = Fix(range_clamp(data[k]))
		end
		run_loops!(dsp, s, n_env)
	end
	wavwrite(float.(s), filename; Fs=fs)
	return s
end

phi = (1+sqrt(5))/2


function bell()
	T = 4
	lp_exp = -8

	fc = C5; Imax = 4.5
	#fc = C6; Imax = 3
	fm = phi*fc
	#fm = 4/3*fc+2
	#fm = 5/3*fc+2; Imax = 4

	gain_m_exp4 = 1
	gain_m_factor = Imax/pi/(4^gain_m_exp4)

	t = 0:h_env:T
	fa = 1 .- exp.(-t*25)
	gain_c = fa.*exp.(-0.5*t)
	gain_m = gain_m_factor*fa.*exp.(-0.85*t)

	#program, d = fm_program(fc, fm; gain_m_exp4=gain_m_exp4)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/bell.wav", program, t, [d[:gain_m] => gain_m, d[:gain_c] => gain_c])

	fc *= 3/4
	fm = 4/3*fc+2

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/bell_4th.wav", program, t, [d[:gain_m] => gain_m, d[:gain_c] => gain_c])
end

function wood_drum()
	fc = C3
	fm = fc/phi
	Imax = 25/2
	gain_m_exp4 = 2
	T = 2
	lp_exp = -4

	t = 0:h_env:T

	I = Imax*max.(0, 1 .- t/0.02)
	tVmax = 0.04
	V0 = 0.8
	Te = 0.02
	V = min.(t/tVmax*(1-V0) .+ 0.8, exp.(-(t .- tVmax)/Te))

	#program, d = fm_program(fc, fm; gain_m_exp4=gain_m_exp4)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/wood_drum.wav", program, t, [d[:gain_m] => I/pi, d[:gain_c] => V])
end

function brass()
	fc = C4
	fm = fc + 1
	T = 2
	lp_exp = -8
	#Imax = 3; gain_m_exp4 = 0
	Imax = 3.5; gain_m_exp4 = 0
	v = [0,1,0.75,0.63,0]
	#dtv = [0, 85, 86, 256, 86]; Tenv = 0.6
	dtv = [0, 85, 86, 256+512, 86]; Tenv = 1

	tv = cumsum(dtv)
	tv = tv*(Tenv/maximum(tv))

	t = 0:h_env:T

	V = Spline1D(tv, v; k=1)(t)
	I = Imax*V

	#program, d = fm_program(fc, fm; gain_m_exp4=gain_m_exp4)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)	
	synthesize!("../wav/brass.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function clarinet()
	fm = C5
	fc = 3*fm + 0.1
	Imax = 2.0; gain_m_exp4 = 0
	Tenv = 1
	T = 2
	lp_exp = -8

	i = [0,1,1]
	dti = [0, 50, 463+512]
	v = [0,1,1,0]
	dtv = [0, 50, 443+512, 20]
	ti = cumsum(dti)
	tv = cumsum(dtv)
	ti = ti*(Tenv/maximum(tv))
	tv = tv*(Tenv/maximum(tv))

	t = 0:h_env:T

	Ienv = Spline1D(ti, i; k=1)(t)
	V = Spline1D(tv, v; k=1)(t)

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/clarinet.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/clarinet2.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2, m_inst = inst_sina2)
	synthesize!("../wav/clarinet3.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	fm = C4
	fc = 3*fm + 0.1
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2)
	Imax = 0.2
	synthesize!("../wav/pipe.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i)
	Imax = 0.25
	synthesize!("../wav/pipe2.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i, c_inst = inst_sina2)
	Imax = 0.25
	synthesize!("../wav/pipe3.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function bassoon()
	fm = C2
	fc = 5*fm + 2
	Imax = 2.0; gain_m_exp4 = 0
	Tenv = 1
	T = 2
	lp_exp = -8

	i = [0,1,1]
	dti = [0, 100, 463+512]
	v = [0,1,1,0]
	dtv = [0, 100, 443+512, 100]
	ti = cumsum(dti)
	tv = cumsum(dtv)
	ti = ti*(Tenv/maximum(tv))
	tv = tv*(Tenv/maximum(tv))

	t = 0:h_env:T

	Ienv = Spline1D(ti, i; k=1)(t)
	V = Spline1D(tv, v; k=1)(t)

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/bassoon.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4)
	#synthesize!("../wav/bassoon-h.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2)
	synthesize!("../wav/bassoon1.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2)
	#synthesize!("../wav/bassoon1-h.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i)
	synthesize!("../wav/bassoon2.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i)
	#synthesize!("../wav/bassoon2-h.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i, c_inst = inst_sina2)
	synthesize!("../wav/bassoon3.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	Imax = 3.5; gain_m_exp4 = 1
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/bassooni.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4)
	#synthesize!("../wav/bassooni-h.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])

	#program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = triangle_i)
	#synthesize!("../wav/bassooni2.wav", program, t, [d[:gain_m] => Imax*Ienv/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function bass()
	fc = C2
	fm = fc-1
	Imax = 5; gain_m_exp4 = 1
	Te = 0.5
	T = 2
	lp_exp = -8

	t = 0:h_env:T
	fa = 1 .- exp.(-t*100)
	V = fa.*exp.(-t/Te)
	I = Imax*fa.*exp.(-0.5*t/Te)

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/bass.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4)
	#synthesize!("../wav/bass-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2)
	synthesize!("../wav/bass-cs2.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, c_inst = inst_sina2)
	#synthesize!("../wav/bass-cs2-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst=inst_sina2)
	synthesize!("../wav/bass-ms2.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst=inst_sina2)
	#synthesize!("../wav/bass-ms2-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])

	#program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst=triangle_i)
	#synthesize!("../wav/bass-mt.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst=triangle_i)
	#synthesize!("../wav/bass-mt-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function drum()
	T = 2

	fc = C2
	Imax = 25; gain_m_exp4 = 2
	fm = fc/phi

	t = 0:h_env:T

	#fa = 1 .- exp.(-t*200); lp_exp = 0
	fa = 1; lp_exp = -8

	V = fa.*exp.(-3*t)
	I = Imax*fa.*exp.(-85*t)

	#program, d = fm_program(fc, fm; gain_m_exp4=gain_m_exp4)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/drum.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function snare()
	T = 2
	t = 0:h_env:T

	fn = 5000

	fa = 1 .- exp.(-t*200)
	Vn = fa.*exp.(-10*t)
	#Vn = max.(0, 1 .- 5*t)

	fc = C2*2^(7/12)
	Imax = 18; gain_m_exp4 = 2
	fm = fc/phi

	#V = fa.*exp.(-7*t)
	V = max.(0, 1 .- 5*t)
	I = Imax*fa.*exp.(-40*t) .+ 1.5

	program, d = fm_and_noise_program(fc, fm, fn; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/snare.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V, d[:gain_n] => Vn])
end

function hihat()
	T = 1
	t = 0:h_env:T

	fn = fs

	#fa = 1 .- exp.(-t*200)
	Vn = max.(0, 1 .- 20*t)

	gain_m_exp4 = 0
	fc = C2*2^(7/12)
	fm = fc/phi

	V = 0*t
	I = 0*t

	program, d = fm_and_noise_program(fc, fm, fn; gain_m_exp4=gain_m_exp4)
	synthesize!("../wav/hihat.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V, d[:gain_n] => Vn])
end

function keyboard()
	fc = C3
	fm = fc*1.5 + 1
	lp_exp = -8

	Imax = 2.5; gain_m_exp4 = 0

	T = 2
	t = 0:h_env:T

	fa = 1 .- exp.(-t*75)
	V = fa.*exp.(-3*t)
	I = Imax.*fa.*exp.(-1.8*t)

	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard0.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard0-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	#program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4)
	#synthesize!("../wav/keyboard00-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])

	fm = fc + 1
	Imax = 4.8; gain_m_exp4 = 1
	I = Imax.*fa.*exp.(-1.8*t)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard1.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard1-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])

	fm = fc*2 + 1
	Imax = 2.0; gain_m_exp4 = 0
	I = Imax.*fa.*exp.(-1.5*t)
	program, d = fm_program_lp(fc, fm, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard2.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
	program, d = fm_program_lp(fc*2, fm*2, lp_exp; gain_m_exp4=gain_m_exp4, m_inst = inst_sina2)
	synthesize!("../wav/keyboard2-h.wav", program, t, [d[:gain_m] => I/(pi*4^gain_m_exp4), d[:gain_c] => V])
end

function sinewave()
	fc = A4
	T = 4
	t = 0:h_env:T

	freq_c, exp_c = f_to_freq_exp(fc)

	gain_c = Fix(1.0)

	phase_c_addr = 1
	program = [
		(Instruction(inst_acc_imm_to_mem, IContext(phase_c_addr, exp_c)), freq_c),
		(inst_sin, Fix(0)),
		(inst_output_a, Fix(0)),
		(inst_dither_update, Fix(2^-15))
	]

	synthesize!("../wav/sine-approx.wav", program, t, [])

	t = (0:fs*T)/fs
	phase = 2*fc*t
	phase = round.(phase*32768)/32768
	s = sin.(pi*phase)
	wavwrite(s, "../wav/sinewave.wav"; Fs=fs)
end

bell()
#wood_drum()
brass()
clarinet()
bassoon()
bass()
drum()
snare()
hihat()
keyboard()
sinewave()

nothing
