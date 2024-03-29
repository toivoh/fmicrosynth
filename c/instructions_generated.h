// Generated by julia/codegen.jl -- rerun to regenerate
#ifndef __instructions_generated_h
#define __instructions_generated_h

#define INST_NOP            0x0000
#define INST_ENABLE         0x0200
#define INST_DISABLE        0x0300
#define INST_PHASE_UPDATE   0x1000
#define INST_CONTRIBUTE     0x2000
#define INST_MADD_SCALE2    0x3000
#define INST_APPROACH       0x4000
#define INST_SQUARE         0x5d00
#define INST_PULSE          0x5000
#define INST_PULSE_IMM      0x6000
#define INST_SAWTOOTH       0x0000
#define INST_TRIANGLE       0x7c00
#define INST_SINA2          0x8000
#define INST_SIN            0x9000
#define INST_NOISE_UPDATE   0xa000
#define INST_OUTPUT         0xb000
#define INST_OUTPUT_LEFT    0xb000
#define INST_OUTPUT_RIGHT   0xb100
#define INST_OUTPUT_A       0xc000
#define INST_OUTPUT_A_LEFT  0xc000
#define INST_OUTPUT_A_RIGHT 0xc100
#define INST_LOOP_UPDATE    0xd000

#endif // __instructions_generated_h
