FMicrosynth
===========
FMicrosynth is a small programmable sound synthesizer implementation for FPGA. The main design objectives have been to be support
* simple FM synthesis, and
* square/pulse/triangle/sawtooth/noise waveforms

while not using very much FPGA resources (see [space saving considerations](space-saving.md)).

FMicrosynth works like a small processor:
* Custom instruction set for waveform generation
	* No jump instruction - the program repeats in a loop
* Each loop produces one new sample (in 16 bit stereo)
	* The sample rate determines how often new loops are started
* Everything is calculated in 16 bit fixed point, range -1 .. 1 - 1/32768 (represented by integers in the range -32768 .. 32767)
* There's memory for 64 (16 bit) instructions, and 64 (16 bit) data entries
* Depending on the program, a given data entry can be used as either a
	* _parameter_ (such as a gain or pitch), which is updated from the outside, or a
	* _state_ (such as the phase of an oscillator), which is updated by the program itself

The program can be put together from _patches_, small code snippets that each make up an instrument, with associated parameters such as pitch and volume.

There is limited support for envelopes: Instead of changing eg a volume parameter directly from the outside, a patch can take a target value and a speed to approach it.
Beyond that, envelope handling is expected to be done by software.

Usage is described below.
See also
* [instruction set](instructions.md),
* [embedding](embedding.md), and
* [space saving considerations](space-saving.md), including
	* the sine approximation, and
	* phase dithering for improved frequency resolution.

A short demonstration of the synth can be heard at https://youtu.be/o0-lQ3pMrYY

Usage
-----
The steps to using FMicrosynth are:
* Put the processor in reset by setting the `reset` bit to one
* Upload a program
* Take the processor out of reset
* Change the program's parameters over time to control the sound produced by the patches

It is also possible to add/remove/change patches while the processor is running, see below.

The program consists of
* The program memory `code[0] .. code[63]`, containing 16 bit instructions
* The data memory `data[0] .. data[63]`, containing 16 bit signed fixed point numbers with 15 fractional bits

Each parameter is stored at an address `addr` in the program. Most kinds of parameters are stored in `data[addr]`, but some parameters also use fields in `code[addr]`.

Instruction format
------------------
Each entry in `code[]` contains one instruction. The format is

	+---------------+---------------+-------+-----------------------+
	|     opcode    |  scale_code   |       |      addr/sub_op      |
	+---------------+---------------+-------+-----------------------+
	 15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0

Fields:
* `opcode`: Determines which instruction to use, sometimes together with the other fields
* `scale_code`: Encodes a constant value `scale` used by some instructions:
	* 0: `scale = 0`
	* 1-14: `scale = 2^(scale_code-13)`
	* 15: `scale = -4`
* `addr/sub_op`: Used as an address into `data[]`, or to further specify the instruction

When the upper byte is zero, the instruction is a `nop` (no operation).
Apart from `data[addr]`, an instruction in `code[pc]` can also read/write `data[pc]`, which is often used as a parameter to the instruction.

Example program
---------------
First, put the processor in reset.
Fill `code[]` with zeros (`nop`s), and `data[]` with zeros (as default parameter values/initial states).

Now, set up the program:

	// square wave patch
	code[0+0] = INST_APPROACH | SCALE(-8) | ADDR(0+4);    // data[0+0] = vol_left
	code[0+1] = INST_APPROACH | SCALE(-8) | ADDR(0+5);    // data[0+1] = vol_right
	code[0+2] = INST_PHASE_UPDATE | SCALE(0) | ADDR(0+3); // data[0+2] = freq_delta
	code[0+3] = INST_SQUARE;
	code[0+4] = INST_CONTRIBUTE | ADDR(61); 
	code[0+5] = INST_CONTRIBUTE | ADDR(62);

	// triangle wave patch
	code[6+0] = INST_APPROACH | SCALE(-8) | ADDR(6+4);    // data[6+0] = vol_left
	code[6+1] = INST_APPROACH | SCALE(-8) | ADDR(6+5);    // data[6+1] = vol_right
	code[6+2] = INST_PHASE_UPDATE | SCALE(0) | ADDR(6+3); // data[6+2] = freq_delta
	code[6+3] = INST_TRIANGLE;
	code[6+4] = INST_CONTRIBUTE | ADDR(61);
	code[6+5] = INST_CONTRIBUTE | ADDR(62);

	// epilogue
	code[61] = INST_OUTPUT_LEFT  | ADDR(61);
	code[62] = INST_OUTPUT_RIGHT | ADDR(62);
	code[63] = INST_LOOP_UPDATE;

See [c/instructions.h](c/instructions.h) and [c/instructions_generated.h](c/instructions.h) for the instruction definitions.
The `SCALE` and `ADDR` macros are used to put values for the `scale_code` and `addr` fields into the instructions (`SCALE(n)` gives `scale = 2^n`).

The program contains
* two patches: a square wave and a triangle wave, and
* an epilogue to output the resulting samples and update the processor state.

Take the processor out of reset. There should be no sound yet, because the volumes and frequencies are set to zero.

Now, we can start to change some parameters:
* The left/right volume parameters are stored in `(data[0+0], data[0+1])` for the square wave patch, and `(data[6+0], data[6+1])` for the triangle wave patch.
* The frequencies for the two patches are stored in `data[0+2]` and `data[6+2]`, respectively.

Try setting the volumes to 0.5 (16384), and the frequencies eg somewhere in the range 0.03 to 0.1 (1000 to 3000). Now you should hear the two patches!

Setting volume/gain parameters
------------------------------
A volume parameter at `addr` is simply stored in `data[addr]`, as a value between 0.0 and 1.0-1/32768 (an integer between 0 and 32767)

Setting pitch parameters
------------------------
Setting pitch parameters is a bit more complex than volume parameters, because the 16 bits in a `data` entry are not enough to get good frequency resolution over all octaves.
To improve the resolution, octave information is stored in the `scale_code` field in `code[addr]`, while the scaled frequency is stored in `data[addr]`.

To set a pitch parameter at address `addr`, set

	code[addr] = CHANGE_SCALE(code[addr], n);
	data[addr] = delta;

The `CHANGE_SCALE` macro updates the `scale_code` field of the instruction (which is located in the upper byte).
The resulting frequency is (`delta` as integer)

	f = fs * 2^n * delta / 65536

where `fs` is the sampling frequency, `0 <= delta <= 32767`, and `n <= 0`.
To get the best frequency resolution, use a value for `n` that is as low as possible but still makes `delta <= 32767`.

Putting together a program from patches
---------------------------------------
The following template can be used to assemble a program from patches:

	source patch 1
	output patch
	source patch 2
	output patch
	...
	source patch N
	output patch
	<as many nops as needed to fill out the space>
	epilogue

Parts:
* source patch: creates one voice
* output patch: mixes the output of the preceding patch into the output channels
* `nop`s: unused instructions
* epilogue:
	* outputs and resets the accumulated output from the patches
	* updates internal state for the next loop

We first consider the epilogue and the output patch, and then list some useful source patches.

A patch can be placed anywhere in `code[]` where it fits, but some of the instructions have to be adjusted based on the address. In the code below, `base` refers to the address where the first instruction of a patch is placed.

Unless otherwise noted, initialize all `data[]` entries to zero. Keep the processor in reset while setting up the code and data.

Some of the patches below contain explicit `nop` instructions. This is used when the patch needs additional space in `data` to store states (all `data` entries that don't hold parameters are generally used for states).

### The epilogue
For stereo output, use the epilogue

	code[base+0] = INST_OUTPUT_LEFT  | ADDR(base+0); // state: left  sample
	code[base+1] = INST_OUTPUT_RIGHT | ADDR(base+1); // state: right sample
	code[base+2] = INST_LOOP_UPDATE; // Needed for full frequency resolution. <state: loop counter>

The samples for the left and right channels are accumulated in `data[mix_addr_left]` and `data[mix_addr_right]`, where

	mix_addr_left  = base
	mix_addr_right = base+1

These addresses are needed to set up the output patches.

The state in `data[base+2]` acts as a running loop counter, which increments by one for every sample produced.

### The output patch
For stereo output, use the output patch

	code[base+0] = INST_CONTRIBUTE | ADDR(mix_addr_left); 
	code[base+1] = INST_CONTRIBUTE | ADDR(mix_addr_right);
	code[base+2] = INST_APPROACH | SCALE(-8) | ADDR(base+0); // data[base+2] = vol_left
	code[base+3] = INST_APPROACH | SCALE(-8) | ADDR(base+1); // data[base+3] = vol_right

This will mix the output from the preceding source patch into the left and right output samples.
The left/right output volume parameters are in `data[base+2]` and `data[base+3]`.

The actual output volumes track these volume parameters at a rate set by the `scale_code` fields in `code[base+2]` and `code[base+3]`. A value of -8 seems to work well to avoid glitches when changing volume parameters, but other values can be used to make the tracking slower or faster.

### Simple waveform

	code[base+0] = INST_PHASE_UPDATE | SCALE(0) | ADDR(base+1); // pitch
	code[base+1] = INST_SQUARE; // waveform instruction

The pitch is stored at address `base+0`.

The waveform can be changed by changing `code[base+1]` to the appropriate instruction:

	INST_SQUARE / INST_PULSE / INST_SAWTOOTH / INST_TRIANGLE / INST_SINA2 / INST_SIN

`INST_SINA2` is a piecewise quadratic sine approximation; closer to a sine wave than `INST_TRIANGLE`, but not as close as `INST_SIN` (see [instructions](instructions.md)).

For the pulse wave, use

	code[base+1] = INST_PULSE | SCALE(-n)

to get a pulse wave a with duty cycle `2^-n / 2`.

### Noise

	code[base+0] = INST_PHASE_UPDATE | SCALE(0) | ADDR(base+1); // pitch
	code[base+1] = INST_NOP;
	code[base+2] = INST_NOISE_UPDATE;

Initialize `data[base+2]` with any nonzero value.

The pitch is stored at address `base+0`, and is used to control the frequency with which the noise waveform is updated.
For regular waveforms, it doesn't make sense to use a frequency above half the sampling frequency, but the noise waveform is usable up to the full sampling frequency.

### Pulse wave with arbitrary duty cycle

	code[base+0] = INST_PHASE_UPDATE | SCALE(0) | ADDR(base+1); // pitch
	code[base+1] = INST_NOP;
	code[base+2] = INST_PULSE_IMM; // data[base+2] = 1-2*duty 

The pitch is stored at address `base+0`, and the duty cycle is `(1-data[base+2])/2`.

### Simple (two operator) FM voice

	code[base+0] = INST_APPROACH | SCALE(-8) | ADDR(base+4);    // modulation index
	code[base+1] = INST_PHASE_UPDATE | SCALE(0) | ADDR(base+5); // carrier pitch
	code[base+2] = INST_PHASE_UPDATE | SCALE(0) | ADDR(base+3); // modulator pitch
	code[base+3] = INST_SIN; // modulator waveform
	code[base+4] = INST_MADD_SCALE2 | SCALE(I_scale) | ADDR(base+5);
	code[base+5] = INST_SIN; // carrier waveform

The carrier/modulator pitches are at address `base+1, base+2`. The modulation index I is given by

	I = data[base+0] * pi * 4^I_scale

where `I_scale` is the scale value of `code[base+4]`. This allows to use a maximal modulation index of `I = pi * 16`, or approximately 50.

The actual modulation index tracks the value in `data[base+0]` at a rate given by the `scale_code` field of `code[base+0]`.
A value of -8 seems to work well to avoid glitches when changing modulation index, but other values can be used to make the tracking slower or faster.

The modulator and carrier waveforms can be changed by replacing the instructions at `code[base+3]` and `code[base+5]` respectively, with other waveform instructions (see [instructions](instructions.md)).

Changing patches on the fly
---------------------------
A patch can be added to an existing program if there is hole of the approriate size (filled with `nop`s) to put it in.

The program memory can be changed at any time, but it's best to make sure that instructions and patches are not executed in a half-updated state.
Some useful tools to achieve this:
* As long as the high byte of `code[addr]` is zero, the instruction is treated as a `nop`
* The `disable` instruction makes the processor treat all instructions as `nop`s, until it encounters an `enable` instruction
  (these instructions also work the same regardless of the value of the low byte in `code[addr]`)

The `enable/disable` instructions can be used to disable a range of `code` containing one or more patches, so that their `code` and `data` can be manipulated freely:
1. Replace the last instruction with `INST_ENABLE`.
2. Replace the first instruction with `INST_DISABLE`.
3. Set up all data values as desired, and all instructions except the first and last.
4. Write the first instruction, overwriting the `disable` instruction.
5. Wait for the loop counter to change, to make sure that we don't remove the `enable` instruction while the `disable` instruction that we replaced is still in effect.
6. Write the last instruction.

There is a short time between steps 1 and 2, and between steps 4 and 6, where the whole patch is executing except for the last instruction, and the patch needs to be able to handle this. One way is to add a `nop` at the end. Forunately, the output patch handles this fine: The last instruction is used to track one of the output volumes, and the difference should be minimal if this step is skipped for a sample.
