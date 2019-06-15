Instruction set
===============
See [README.md](README.md) for the instruction format.

Instructions can read and write the following operands:
* `a`, the accumulator register. This is updated by most instructions.
* `mem`, which will be used as a shorthand for `data[addr]`, where `addr` is taken from the instruction's `addr` field
* `imm`, which will be used as a shorthand for `data[pc]`, where `pc` is the instruction's address
There's also some read-only operands:
* `scale`, the constant specified by the instruction´s `scale` field. Read only.
* `dither`, a tiny value in the range 0 <= dither < 1/32768, which changes from sample to sample.
  Used to improve long term accuracy of values that accumulate over time.
  Updated by the special `loop_update` instruction.
    * If an instruction uses a math operation without specifying `dither`, a `dither` value causing round-to-nearest is used.

Instructions can also depend on the `overflow` flag, updated by some instructions to indicate whether the result was in the representable range -1 .. 1-1/32768.

When the processor has finished one loop through the program, it waits to start execution at `pc = 0` until a trigger signal is received. This trigger signal is provided by the system, and sets the sample rate.

Instructions
------------
See [c/instructions_generated.h](c/instructions_generated.h) for the binary representation of each instruction.
See [c/instructions.h](c/instructions.h) for the macros used to set fields in the instructions below:
* `ADDR(addr)` sets the `addr` field
* `SCALE_CODE` and `SCALE` set the `scale_code` field
	* `SCALE(n)` corresponds to
		* `scale = 0`, for `n` = -13
		* `scale = 2^n`, for `n` = -12 .. 1
		* `scale = -4`, for `n` = 2

The following constant values are used below:
* `maxval`: The biggest  representable value, 32767/32768 = 1 - 1/32768
* `minval`: The smallest representable value, -32768/32768 = -1

### nop

	code[pc] = INST_NOP;

Used to fill out any unused instruction slots. It's enough to set the high byte of the instruction to 0 to make it a `nop`.

### disable

	code[pc] = INST_DISABLE;

Make all instructions be treated as `nop`s until the next `enable` instruction.

### enable

	code[pc] = INST_ENABLE;

Enable execution of instructions again.

### phase_update

	code[pc] = INST_PHASE_UPDATE | SCALE(n) | ADDR(addr);

	a = mem += scale*imm + dither

Update the phase of an oscillator. The new phase value is available in `a`.
For the best frequency resolution, the `scale` value should be used to set the octave, while keeping the frequency value in `imm` as big as possible. Then the dithering will give improved frequency stability for lower octaves.

Sets the value of the `overflow` flag to indicate whether the result wrapped around (used by `noise_update`).

### contribute

	code[pc] = INST_CONTRIBUTE | ADDR(addr);

	mem = clamp(mem + imm*a)

Useful to mix the output of a patch into an output sample, with volume given by `imm`. The value of `a` is preserved so that eg two `contribute` instructions in a row can be used for stereo output.

### madd_scale2

	code[pc] = INST_MADD_SCALE2 | SCALE(n) | ADDR(addr);

	a = scale^2*(imm*a) + mem

Useful to for modulating one oscillator (with phase stored in `mem`) with the value `a`. The `scale` value can be used for up to 16x amplification.

### approach

	code[pc] = INST_APPROACH | SCALE(n) | ADDR(addr);

	a = mem = clamp(mem + scale*(imm - mem) + dither)

Makes the value in `mem` approach the value in `imm`, at a rate controlled by `scale`. Useful to low pass filter parameters such as volumes, which can create audible noise if they are changed stepwise. The dithering makes sure that `mem` eventually converges to `imm`, if `imm` is held constant for long enough time.

### square

	code[pc] = INST_SQUARE;

	a = (a >= 0) ? maxval : minval

Square wave; special case of `pulse`.

### pulse

	code[pc] = INST_PULSE | SCALE(n);

	a = (a >= -1 + scale ? maxval : minval)

Pulse wave with duty cycle given by `scale`: `scale = 1` gives a square wave, `scale = 2^-1, 2^-2,` etc. give successively narrower pulses (the narrow part has value `minval`).

### pulse_imm

	code[pc] = INST_PULSE_IMM;

	a = (a >= imm ? maxval : minval)

Pulse wave with duty cycle given through `imm`. `imm = 0` gives a square wave.

### sawtooth

	code[pc] = INST_SAWTOOTH;

	a = a

This is a `nop`.
But since many patches use the `data[]` entry of the waveform instruction to store the phase of the oscillator, it's often necessary to use a `nop` in the code when generating a sawtooth wave.

### triangle

	code[pc] = INST_TRIANGLE;

	a = triangle(a)

Triangle wave:

	triangle( 0)   = triangle(-1) = triangle(1) = 0
	triangle( 0.5) =  1
	triangle(-0.5) = -1

### sina2

	code[pc] = INST_SINA2;

	a = -sina2(a)

Second order sine approximation:

	sina2(t) = 1 - (2*t-1)^2,	t = 0..1
	sina2(t) = -sina2(-t)

and then it repeats. Weaker harmonics than `triangle`, but still noticeable.

### sina

	code[pc] = INST_SIN;

	a = sin(pi*a)

Sine approximation. Useful for FM synthesis.

### noise_update

	code[pc] = INST_NOISE_UPDATE;

	a = lfsr_update(a)
	if (overflow) imm = a

Linear feedback shift register implementation, useful for noise. `imm` must be initialized to a value != 0 to get noise.
Use a `phase_update` instruction just before, to set the `overflow` flag when the phase wraps around. This will trigger an update of the shift register, and let's you control the frequency of the noise.

The accompanying `phase_update` instruction can use a value of `scale=2` to be able to reach up the full noise frequency.

### output

	code[pc] = INST_OUTPUT | SCALE_CODE(channel) | ADDR(addr);

	output[scale_code] = imm; mem = 0

Store `imm` as an output sample. Use `scale_code = 0` for left channel and `scale_code = 1` for right, or use `INST_OUTPUT_LEFT` and `INST_OUTPUT_RIGHT` directly.
Typical usage is to set `addr = pc` to zero out `imm` for the next loop. This will allow all patches to add their contributions into it.

### output_a

	code[pc] = INST_OUTPUT_A | SCALE_CODE(channel);

	output[scale_code] = a

Like `output`, but output the value in `a` and don't reset anything.

### loop_update

	code[pc] = INST_LOOP_UPDATE;

	dither = bit_reverse(imm); a = imm += 1

Updates the `dither` state. Should be executed once per loop to make phase dithering work and get full frequency resolution.
The value of `imm = data[pc]` can be read as running loop counter.
