#ifndef LIBCXT_CONV2D_H_
#define LIBCXT_CONV2D_H_

#include <stdint.h>
#include <stddef.h>

static inline size_t __riscv_xt_conv2d(uintptr_t in_ptr, uintptr_t w_ptr, const uint32_t params) {
  size_t rd;
  (void)params;
  register uintptr_t rs1 __asm__("a0") = in_ptr;
  register uintptr_t rs2 __asm__("a1") = w_ptr;
  __asm__ volatile (".insn r 0x2b, 1, 0, %0, %1, %2"
                    : "=r"(rd)
                    : "r"(rs1), "r"(rs2));
  return rd;
}

static inline size_t __riscv_xt_maxpool2d(uintptr_t in_ptr, const uint32_t params) {
  size_t rd;
  (void)params;
  register uintptr_t rs1 __asm__("a0") = in_ptr;
  __asm__ volatile (".insn r 0x2b, 2, 0, %0, %1, x0"
                    : "=r"(rd)
                    : "r"(rs1));
  return rd;
}

static inline size_t __riscv_xt_act(uintptr_t in_ptr, const uint32_t params) {
  size_t rd;
  (void)params;
  register uintptr_t rs1 __asm__("a0") = in_ptr;
  __asm__ volatile (".insn r 0x2b, 3, 0, %0, %1, x0"
                    : "=r"(rd)
                    : "r"(rs1));
  return rd;
}

#endif // LIBCXT_CONV2D_H_
