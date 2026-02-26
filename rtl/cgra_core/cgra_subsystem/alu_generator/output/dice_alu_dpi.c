/*
 * AUTO-GENERATED C DPI model — DO NOT EDIT.
 * name: dice_alu
 */

#include <stdint.h>

#define OPCODE_ADD_U32 0x0
#define OPCODE_SUB_U32 0x1
#define OPCODE_MUL_LO_U32 0x2
#define OPCODE_MAD_U32 0x3
#define OPCODE_DIV_U32 0x4
#define OPCODE_REM_U32 0x5
#define OPCODE_ADD_S32 0xA
#define OPCODE_SUB_S32 0xB
#define OPCODE_MUL_LO_S32 0xC
#define OPCODE_DIV_S32 0xD
#define OPCODE_REM_S32 0xE
#define OPCODE_AND_B32 0x14
#define OPCODE_OR_B32 0x15
#define OPCODE_XOR_B32 0x16
#define OPCODE_NOT_B32 0x17
#define OPCODE_SHL_B32 0x1E
#define OPCODE_SHR_U32 0x1F
#define OPCODE_SHR_S32 0x20
#define OPCODE_MIN_U32 0x28
#define OPCODE_MAX_U32 0x29
#define OPCODE_MIN_S32 0x2A
#define OPCODE_MAX_S32 0x2B
#define OPCODE_ADD_F32 0xC8
#define OPCODE_SUB_F32 0xC9
#define OPCODE_MUL_F32 0xCA
#define OPCODE_DIV_F32 0xCB
#define OPCODE_MAD_F32 0xCC
#define OPCODE_MIN_F32 0xCD
#define OPCODE_MAX_F32 0xCE
#define OPCODE_SET_EQ_U32 0x32
#define OPCODE_SET_NE_U32 0x33
#define OPCODE_SET_LT_U32 0x34
#define OPCODE_SET_LE_U32 0x35
#define OPCODE_SET_GT_U32 0x36
#define OPCODE_SET_GE_U32 0x37
#define OPCODE_SET_LT_S32 0x38
#define OPCODE_SET_GT_S32 0x39
#define OPCODE_SEL 0x64

#ifdef __cplusplus
extern "C" {
#endif

void dice_alu_eval_comb(uint64_t in0, uint64_t in1, uint64_t in2, uint64_t in3, uint32_t opcode, uint64_t* out0, uint64_t* out1) {
    uint64_t in[4] = { in0, in1, in2, in3 };
    uint64_t out[2] = {0};
    const uint64_t in_mask[4] = { ((1ULL << 32) - 1ULL), ((1ULL << 32) - 1ULL), ((1ULL << 32) - 1ULL), ((1ULL << 1) - 1ULL) };
    const uint64_t out_mask[2] = { ((1ULL << 32) - 1ULL), ((1ULL << 1) - 1ULL) };
    for (int i=0;i<4;++i) in[i] &= in_mask[i];
    switch (opcode) {
    case OPCODE_ADD_U32: {
        out[0] = (in[0] + in[1]);
        break;
    }
    case OPCODE_SUB_U32: {
        out[0] = (in[0] - in[1]);
        break;
    }
    case OPCODE_MUL_LO_U32: {
        out[0] = (in[0] * in[1]);
        break;
    }
    case OPCODE_MAD_U32: {
        out[0] = (in[0] * in[1]) + in[2];
        break;
    }
    case OPCODE_DIV_U32: {
        out[0] = (in[1] == 0) ? 0 : (in[0] / in[1]);
        break;
    }
    case OPCODE_REM_U32: {
        out[0] = (in[1] == 0) ? 0 : (in[0] % in[1]);
        break;
    }
    case OPCODE_ADD_S32: {
        out[0] = (uint64_t)((int32_t)in[0] + (int32_t)in[1]);
        break;
    }
    case OPCODE_SUB_S32: {
        out[0] = (uint64_t)((int32_t)in[0] - (int32_t)in[1]);
        break;
    }
    case OPCODE_MUL_LO_S32: {
        out[0] = (uint64_t)((int32_t)in[0] * (int32_t)in[1]);
        break;
    }
    case OPCODE_DIV_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (b == 0) ? 0 : (uint64_t)(a / b);
        break;
    }
    case OPCODE_REM_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (b == 0) ? 0 : (uint64_t)(a % b);
        break;
    }
    case OPCODE_AND_B32: {
        out[0] = in[0] & in[1];
        break;
    }
    case OPCODE_OR_B32: {
        out[0] = in[0] | in[1];
        break;
    }
    case OPCODE_XOR_B32: {
        out[0] = in[0] ^ in[1];
        break;
    }
    case OPCODE_NOT_B32: {
        out[0] = ~in[0];
        break;
    }
    case OPCODE_SHL_B32: {
        out[0] = in[0] << (in[1] & 31);
        break;
    }
    case OPCODE_SHR_U32: {
        out[0] = in[0] >> (in[1] & 31);
        break;
    }
    case OPCODE_SHR_S32: {
        out[0] = (uint64_t)(((int32_t)in[0]) >> (in[1] & 31));
        break;
    }
    case OPCODE_MIN_U32: {
        out[0] = (in[0] < in[1]) ? in[0] : in[1];
        break;
    }
    case OPCODE_MAX_U32: {
        out[0] = (in[0] > in[1]) ? in[0] : in[1];
        break;
    }
    case OPCODE_MIN_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (uint64_t)((a < b) ? a : b);
        break;
    }
    case OPCODE_MAX_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (uint64_t)((a > b) ? a : b);
        break;
    }
    case OPCODE_ADD_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = a + b;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_SUB_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = a - b;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_MUL_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = a * b;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_DIV_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = (b == 0.0f) ? 0.0f : (a / b);
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_MAD_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float c = *((float*)&in[2]);
        float res = (a * b) + c;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_MIN_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = (a < b) ? a : b;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_MAX_F32: {
        float a = *((float*)&in[0]);
        float b = *((float*)&in[1]);
        float res = (a > b) ? a : b;
        out[0] = *((uint32_t*)&res);
        break;
    }
    case OPCODE_SET_EQ_U32: {
        out[1] = (in[0] == in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_NE_U32: {
        out[1] = (in[0] != in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LT_U32: {
        out[1] = (in[0] < in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LE_U32: {
        out[1] = (in[0] <= in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GT_U32: {
        out[1] = (in[0] > in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GE_U32: {
        out[1] = (in[0] >= in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LT_S32: {
        out[1] = ((int32_t)in[0] < (int32_t)in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GT_S32: {
        out[1] = ((int32_t)in[0] > (int32_t)in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SEL: {
        out[0] = (in[3] ? in[0] : in[1]);
        break;
    }
    default: out[0] = 0ULL; out[1] = 0ULL; break;
    }
    if (out0) *out0 = (out[0] & out_mask[0]); if (out1) *out1 = (out[1] & out_mask[1]);
}

void dice_alu_cycle(uint64_t in0, uint64_t in1, uint64_t in2, uint64_t in3, uint32_t opcode, uint64_t* out0, uint64_t* out1) {
    uint64_t in[4] = { in0, in1, in2, in3 };
    uint64_t out[2] = {0};
    const uint64_t in_mask[4] = { ((1ULL << 32) - 1ULL), ((1ULL << 32) - 1ULL), ((1ULL << 32) - 1ULL), ((1ULL << 1) - 1ULL) };
    const uint64_t out_mask[2] = { ((1ULL << 32) - 1ULL), ((1ULL << 1) - 1ULL) };
    for (int i=0;i<4;++i) in[i] &= in_mask[i];
    switch (opcode) {
    case OPCODE_ADD_U32: {
        out[0] = (in[0] + in[1]);
        break;
    }
    case OPCODE_SUB_U32: {
        out[0] = (in[0] - in[1]);
        break;
    }
    case OPCODE_MUL_LO_U32: {
        out[0] = (in[0] * in[1]);
        break;
    }
    case OPCODE_MAD_U32: {
        out[0] = (in[0] * in[1]) + in[2];
        break;
    }
    case OPCODE_DIV_U32: {
        static uint64_t div_u32_pipe_in[2][4] = {0};
        static int div_u32_valid[2] = {0};
        for (int i=1; i>0; --i) {
          for (int j=0;j<4;++j) div_u32_pipe_in[i][j] = div_u32_pipe_in[i-1][j];
          div_u32_valid[i] = div_u32_valid[i-1];
        }
        for (int j=0;j<4;++j) div_u32_pipe_in[0][j] = in[j];
        div_u32_valid[0] = 1;
        if (div_u32_valid[1]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = div_u32_pipe_in[1][j];
          out[0] = (stage[1] == 0) ? 0 : (stage[0] / stage[1]);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_REM_U32: {
        static uint64_t rem_u32_pipe_in[2][4] = {0};
        static int rem_u32_valid[2] = {0};
        for (int i=1; i>0; --i) {
          for (int j=0;j<4;++j) rem_u32_pipe_in[i][j] = rem_u32_pipe_in[i-1][j];
          rem_u32_valid[i] = rem_u32_valid[i-1];
        }
        for (int j=0;j<4;++j) rem_u32_pipe_in[0][j] = in[j];
        rem_u32_valid[0] = 1;
        if (rem_u32_valid[1]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = rem_u32_pipe_in[1][j];
          out[0] = (stage[1] == 0) ? 0 : (stage[0] % stage[1]);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_ADD_S32: {
        out[0] = (uint64_t)((int32_t)in[0] + (int32_t)in[1]);
        break;
    }
    case OPCODE_SUB_S32: {
        out[0] = (uint64_t)((int32_t)in[0] - (int32_t)in[1]);
        break;
    }
    case OPCODE_MUL_LO_S32: {
        out[0] = (uint64_t)((int32_t)in[0] * (int32_t)in[1]);
        break;
    }
    case OPCODE_DIV_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (b == 0) ? 0 : (uint64_t)(a / b);
        break;
    }
    case OPCODE_REM_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (b == 0) ? 0 : (uint64_t)(a % b);
        break;
    }
    case OPCODE_AND_B32: {
        out[0] = in[0] & in[1];
        break;
    }
    case OPCODE_OR_B32: {
        out[0] = in[0] | in[1];
        break;
    }
    case OPCODE_XOR_B32: {
        out[0] = in[0] ^ in[1];
        break;
    }
    case OPCODE_NOT_B32: {
        out[0] = ~in[0];
        break;
    }
    case OPCODE_SHL_B32: {
        out[0] = in[0] << (in[1] & 31);
        break;
    }
    case OPCODE_SHR_U32: {
        out[0] = in[0] >> (in[1] & 31);
        break;
    }
    case OPCODE_SHR_S32: {
        out[0] = (uint64_t)(((int32_t)in[0]) >> (in[1] & 31));
        break;
    }
    case OPCODE_MIN_U32: {
        out[0] = (in[0] < in[1]) ? in[0] : in[1];
        break;
    }
    case OPCODE_MAX_U32: {
        out[0] = (in[0] > in[1]) ? in[0] : in[1];
        break;
    }
    case OPCODE_MIN_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (uint64_t)((a < b) ? a : b);
        break;
    }
    case OPCODE_MAX_S32: {
        int32_t a = (int32_t)in[0];
        int32_t b = (int32_t)in[1];
        out[0] = (uint64_t)((a > b) ? a : b);
        break;
    }
    case OPCODE_ADD_F32: {
        static uint64_t add_f32_pipe_in[1][4] = {0};
        static int add_f32_valid[1] = {0};
        for (int i=0; i>0; --i) {
          for (int j=0;j<4;++j) add_f32_pipe_in[i][j] = add_f32_pipe_in[i-1][j];
          add_f32_valid[i] = add_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) add_f32_pipe_in[0][j] = in[j];
        add_f32_valid[0] = 1;
        if (add_f32_valid[0]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = add_f32_pipe_in[0][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = a + b;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_SUB_F32: {
        static uint64_t sub_f32_pipe_in[1][4] = {0};
        static int sub_f32_valid[1] = {0};
        for (int i=0; i>0; --i) {
          for (int j=0;j<4;++j) sub_f32_pipe_in[i][j] = sub_f32_pipe_in[i-1][j];
          sub_f32_valid[i] = sub_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) sub_f32_pipe_in[0][j] = in[j];
        sub_f32_valid[0] = 1;
        if (sub_f32_valid[0]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = sub_f32_pipe_in[0][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = a - b;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_MUL_F32: {
        static uint64_t mul_f32_pipe_in[1][4] = {0};
        static int mul_f32_valid[1] = {0};
        for (int i=0; i>0; --i) {
          for (int j=0;j<4;++j) mul_f32_pipe_in[i][j] = mul_f32_pipe_in[i-1][j];
          mul_f32_valid[i] = mul_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) mul_f32_pipe_in[0][j] = in[j];
        mul_f32_valid[0] = 1;
        if (mul_f32_valid[0]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = mul_f32_pipe_in[0][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = a * b;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_DIV_F32: {
        static uint64_t div_f32_pipe_in[2][4] = {0};
        static int div_f32_valid[2] = {0};
        for (int i=1; i>0; --i) {
          for (int j=0;j<4;++j) div_f32_pipe_in[i][j] = div_f32_pipe_in[i-1][j];
          div_f32_valid[i] = div_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) div_f32_pipe_in[0][j] = in[j];
        div_f32_valid[0] = 1;
        if (div_f32_valid[1]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = div_f32_pipe_in[1][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = (b == 0.0f) ? 0.0f : (a / b);
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_MAD_F32: {
        static uint64_t mad_f32_pipe_in[2][4] = {0};
        static int mad_f32_valid[2] = {0};
        for (int i=1; i>0; --i) {
          for (int j=0;j<4;++j) mad_f32_pipe_in[i][j] = mad_f32_pipe_in[i-1][j];
          mad_f32_valid[i] = mad_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) mad_f32_pipe_in[0][j] = in[j];
        mad_f32_valid[0] = 1;
        if (mad_f32_valid[1]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = mad_f32_pipe_in[1][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float c = *((float*)&stage[2]);
          float res = (a * b) + c;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_MIN_F32: {
        static uint64_t min_f32_pipe_in[1][4] = {0};
        static int min_f32_valid[1] = {0};
        for (int i=0; i>0; --i) {
          for (int j=0;j<4;++j) min_f32_pipe_in[i][j] = min_f32_pipe_in[i-1][j];
          min_f32_valid[i] = min_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) min_f32_pipe_in[0][j] = in[j];
        min_f32_valid[0] = 1;
        if (min_f32_valid[0]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = min_f32_pipe_in[0][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = (a < b) ? a : b;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_MAX_F32: {
        static uint64_t max_f32_pipe_in[1][4] = {0};
        static int max_f32_valid[1] = {0};
        for (int i=0; i>0; --i) {
          for (int j=0;j<4;++j) max_f32_pipe_in[i][j] = max_f32_pipe_in[i-1][j];
          max_f32_valid[i] = max_f32_valid[i-1];
        }
        for (int j=0;j<4;++j) max_f32_pipe_in[0][j] = in[j];
        max_f32_valid[0] = 1;
        if (max_f32_valid[0]) {
          uint64_t stage[4];
          for (int j=0;j<4;++j) stage[j] = max_f32_pipe_in[0][j];
          float a = *((float*)&stage[0]);
          float b = *((float*)&stage[1]);
          float res = (a > b) ? a : b;
          out[0] = *((uint32_t*)&res);
        } else {
          out[0] = 0ULL;
          out[1] = 0ULL;
        }
        break;
    }
    case OPCODE_SET_EQ_U32: {
        out[1] = (in[0] == in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_NE_U32: {
        out[1] = (in[0] != in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LT_U32: {
        out[1] = (in[0] < in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LE_U32: {
        out[1] = (in[0] <= in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GT_U32: {
        out[1] = (in[0] > in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GE_U32: {
        out[1] = (in[0] >= in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_LT_S32: {
        out[1] = ((int32_t)in[0] < (int32_t)in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SET_GT_S32: {
        out[1] = ((int32_t)in[0] > (int32_t)in[1]) ? 1 : 0;
        break;
    }
    case OPCODE_SEL: {
        out[0] = (in[3] ? in[0] : in[1]);
        break;
    }
    default: out[0] = 0ULL; out[1] = 0ULL; break;
    }
    if (out0) *out0 = (out[0] & out_mask[0]); if (out1) *out1 = (out[1] & out_mask[1]);
}

#ifdef __cplusplus
}
#endif
