Space Saving Considerations
===========================
* As little as possible is done in parallel; the necessary resources are time shared instead
* Everything is built around a single multiply-add unit -- many FPGAs have a bunch of them to spare
* Instead of a sine table, a piecewise 4th order polynomial approximation is used (see below)
* The 64 entry width of the code and data memories allows to store 64x1 bits per LUT on Spartan 6
* The processor is paused for any cycle with an external memory access, which allows to use single ported memories for code and data
* A dithering scheme is used to improve the relative frequency accuracy of oscillators beyond that supported by a 16 bit phase angle

The sine approximation
----------------------
A sine function approximation is needed for FM synthesis.
The function `sin(pi/2*t)` is approximated over the interval `[0,2]` (one half-cycle) using the polynomial

	f(t) = 1 - 6/5*(t-1)^2 + 1/5*(t-1)^4

For `[-2,0]` (the other half-cycle), `sin(pi/2*t)` is approximated by `-f(-t)`. Then the approximation repeats with a period of 4, just like `sin(pi/2*t)`.

This is not a pure sine wave, but it's quite close. Except for the fundamental there's odd harmonics:
the 3rd at -48 dB from the fundamental, the 5th at -70 dB, the 7th at -84 dB, the 9th at -95 dB, the 11th at -104 dB,
and then we're beyond the signal-to-noise ratio that we can get with a 16 bit representation.

On top of the approximation error, there's a little roundoff error when the `sin` instruction evaluates the polynomial, with a signal-to-noise ratio of above 96 dB to the true polynomial.

The file [wav/sine-approx.wav](wav/sine-approx.wav) contains a sine wave generated using the `sin` instruction, which can be compared to a true sine wave in [wav/sinewave.wav](wav/sinewave.wav). The sine approximation might have a little more color, but they're close. Regardless, the sine approximation seems to be perfectly usable for FM synthesis, as most instrument examples in the [wav/] directory have been generated using it.

Phase dithering for improved frequency accuracy
-----------------------------------------------
16 bits of phase angle is not enough to represent low note frequencies in a satisfactory way. Consider a 20 Hz tone, played at a sample rate of 48 kHz. With 16 bits of phase, the change in phase from one sample to the next should be

	delta_phase = 20/48000*65536 = 27.3

The two closest frequencies that we can represent are `delta_phase = 27`, which gives `f = 19.8 Hz`, and `delta_phase = 28`, which gives `f = 20.5 Hz`. The distance between these notes is

	log2(28/27) * 1200 = 63 cents = 0.63 semitones

almost 2/3 of a semitone! This is the worst case though, the accuracy only improves with rising frequency. At 12000 Hz, we get `delta_phase = 16384`, and the distance to the next representable frequency is `log2(16385/16384) * 1200` = 0.11 cents, quite acceptable.

To improve the accuracy at low frequencies, DSPSynth uses _phase dithering_:
The frequency is represented as `2^-n*fn`, where `fn` can be made to be between 16384 and 32767.
Each sample, the phase is updated according to

	phase := floor(phase + 2^-n*fn + dither)

where 0.0 <= dither < 1.0 varies quickly between different values.

For our 20 Hz example, `delta_phase = 2^-10*27962 = 27 + 2^-10*314`. Over the course of 1024 samples (2.1 ms), the uppermost 10 bits of `dither` will have taken on all possible combinations, making the calculation round up instead of down in 314 cases, so we have gained 10 bits of frequency accuracy. The distance to the next representable frequency is now `log2(27963/27962) * 1200` = 0.06 cents.
