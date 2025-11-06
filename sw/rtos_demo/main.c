#include <stdint.h>
#include <stdio.h>
#include "libcxt-conv2d.h"

#define DMA_BASE      0x88000000UL
#define CONV_PARAMS   (DMA_BASE + 0x100)

static volatile uint8_t input_tensor[32*32*3] __attribute__((aligned(64)));
static volatile uint8_t weights_tensor[3*3*16] __attribute__((aligned(64)));
static volatile uint8_t output_tensor[30*30*16] __attribute__((aligned(64)));

static inline void write32(uintptr_t addr, uint32_t val) {
  *(volatile uint32_t *)addr = val;
}

static inline void write64(uintptr_t addr, uint64_t val) {
  *(volatile uint64_t *)addr = val;
}

static inline void enable_cop(void) {
  asm volatile ("csrw mxstatus, %0" :: "r"(0xc1038100));
}

int main(void) {
  printf("cnn demo start\n");
  enable_cop();

  // Populate dummy parameters
  write64(DMA_BASE + 0x00, (uintptr_t)input_tensor);
  write64(DMA_BASE + 0x08, (uintptr_t)output_tensor);
  write64(DMA_BASE + 0x10, sizeof(output_tensor) / 16);
  write32(DMA_BASE + 0x18, 15);
  write32(DMA_BASE + 0x20, 0);

  write32(DMA_BASE + 0x40, 32);
  write32(DMA_BASE + 0x48, 32);
  write32(DMA_BASE + 0x50, 16);
  write32(DMA_BASE + 0x58, 3);
  write32(DMA_BASE + 0x60, 1);

  size_t status = __riscv_xt_conv2d((uintptr_t)input_tensor, (uintptr_t)weights_tensor, 0);
  if (status) {
    printf("conv failed %lu\n", (unsigned long)status);
    return -1;
  }

  status = __riscv_xt_act((uintptr_t)output_tensor, 0);
  if (status) {
    printf("act failed %lu\n", (unsigned long)status);
    return -2;
  }

  uint32_t checksum = 0;
  for (size_t i = 0; i < sizeof(output_tensor); ++i) {
    checksum += output_tensor[i];
  }

  printf("cnn done checksum=0x%08x\n", checksum);
  while (1) {
    asm volatile ("wfi");
  }
  return 0;
}
