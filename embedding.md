Embedding FMicrosynth
=====================
The top module is `fmicrosynth`, with interface

    `define INST_BITS 16

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

        output signed [DATA_BITS-1:0] sample_l, sample_r, // output samples
        output running
    );

The `ADDR_BITS` parameter can be set to values up to 7, and determines the size of the `code[]` and `data[]` memories. The other parameters should not be changed.

The synth will be paused as long as `reset` is high, and the program counter will be reset to zero.

The synth is also paused during any cycle that the read enable `mem_re` or any of the four byte write enables `mem_bwe` are high. 
The shared read/write address `mem_addr` maps directly to the processor's address space. The upper two bytes of the read and write data `mem_rd` and `mem_wd` map to `code[mem_addr]`, and the lower two bytes to `data[mem_addr]`.
The read result from `mem_addr` is available in `mem_rd` during the same cycle (as long as `mem_re` is high), and the write of the data in `mem_wd` to `mem_addr` is executed at the next positive clock edge (according to the pattern in `mem_bwe`).

The output samples are available in `sample_l` and `sample_r`. After the synth has completed one loop of the program (updating the samples), it is paused until the next high pulse on the `trigger` input. The samples should be read out before raising `trigger`.

Choosing a sampling frequency
-----------------------------
The sampling frequency is set by the rate of pulses on the trigger signal: one pulse per sample.
The usable sampling frequency is limited by the time that it takes to execute one loop:
* 1-13 cycles per instruction; an average of up to 8 cycles/instruction could be expected for normal code.
* Any cycles needed to serve external memory accesses during the loop, a percentage should probably be added for this.

Example: With 6 address bits, and 10% overhead for external memory accesses, we get an expected `8*64*1.1 = 564` cycles/sample. Clocking the synth at 50 MHz would lead us to choose a sample rate below `(50 MHz)/564 = 88 kHz`.

There might be a point to use a sampling frequency above 48 kHz: High frequency waveforms can contain partials beyond the audible range, and by increasing the sampling frequency, the risk that they will alias down to audible frequencies can be reduced. FM synthesizers typically have to scale down the index of modulation with increasing pitch, to avoid causing too much aliasing.
