Julia code for FMicrosynth
==========================
This directory contains
* `microcode.jl`: Microcode and control flag definitions for FMicrosynth
* `simulator.jl`: Bit and cycle exact simulator of FMicrosynth code, using `microcode.jl`
* `codegen.jl`: Exports the definitions in `microcode.jl` to `../fmicrosynth_generated.vh` (defines) and `../fmicrosynth_generated.v` (microcode state machine)
* `test_dsp.jl`: Tests for some FMicrosynth functionality, based on `simulator.jl`
* `instruments.jl`: Generates the wave files in [../wav/](../wav/) for some example instruments, using `simulator.jl`
* `meta.jl`: Implements the `@constants` and `@flags` macros used by `microcode.jl`

To install Julia, visit https://julialang.org/. This code was developed using Julia 1.1.0.

No packages are required to run `microcode.jl` and `codegen.jl`, but some of the other files use the packages `FixedPointNumbers`, `WAV`, and `Dierckx`. To install one, type eg `]add WAV` at the Julia prompt, and when it's done, press backspace to get back to the regular Julia terminal from the package manager terminal that was activated by pressing `]`.

Most of these program files need you to run `simulator.jl` first (`include("simulator.jl")`) before you can run them. For `codegen.jl`, it's enough to run `microcode.jl` first.
