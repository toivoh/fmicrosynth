#ifndef __instructions_h
#define __instructions_h

#include "instructions_generated.h"

// define address field of instruction
#define ADDR(a) ((a)&127)

// define scale_code field of instruction
#define SCALE_CODE(x) (((x)&15)<<8)

// SCALE(n):
// Gives scale = 2^n,
// except n = 2, which gives scale = -4.
// Must have -12 <= n <= 2
#define SCALE(n) SCALE_CODE((n)+13)

#define SCALE_ZERO       SCALE_CODE(0)
#define SCALE_MINUS_FOUR SCALE_CODE(15)

#define CHANGE_SCALE_CODE(inst, x) (((inst)&0xf0ff) | SCALE_CODE(x))
#define CHANGE_SCALE(inst, n) CHANGE_SCALE_CODE(inst, SCALE(n))

#endif // __instructions_h
