# CNN Accelerator Integration Guide

## Overview
This document captures the integration details for the Xuantie C908 CNN
accelerator implemented in this repository. The accelerator is exposed via the
C908 COP interface and drives a 128-bit AXI master toward system memory.

## COP interface mapping
* `pad_cop_req_*` signals are registered by `cop_agent.v` and forwarded to
  `cnn_accel_top.v`.
* Instruction decode uses `{insn[29:25], insn[14:13]}` with `insn[12]` acting
  as the valid bit.
* Response ID and status propagate through `cnn_accel_top.v` to ensure matching
  with outstanding requests.

### Custom instructions
| Instruction | Encoding summary | Operation |
| ----------- | ---------------- | --------- |
| `xt.conv2d` | opcode `0b0101011`, funct5 `00101`, funct3 `001` | Launch INT8 convolution job. |
| `xt.maxpool2d` | opcode `0b0101011`, funct5 `00110`, funct3 `010` | Launch max-pooling job. |
| `xt.act` | opcode `0b0101011`, funct5 `00111`, funct3 `011` | Launch activation job. |

Immediate field `imm10` encodes runtime parameters such as tensor strides and
activation mode. Additional parameters are supplied via the CSR window. Firmware
is responsible for populating the DMA descriptors before issuing a job.

## CSR map (relative to accelerator base)
| Address | Description |
| ------- | ----------- |
| 0x00    | DMA source base address |
| 0x08    | DMA destination base address |
| 0x10    | DMA transfer length (beats) |
| 0x18    | DMA burst length configuration |
| 0x20    | DMA auto-restart |
| 0x40    | Convolution IFM height |
| 0x48    | Convolution IFM width |
| 0x50    | Convolution output channels |
| 0x58    | Convolution kernel size |
| 0x60    | Convolution stride |
| 0x80..0xBF | Quantization scale and zero-point entries |
| 0xC0..0xCF | Maxpool kernel and stride registers |
| 0xD0      | Activation mode register |

## Clocking and reset
* Single 200 MHz domain shared between the accelerator and AXI bus.
* Reset is active-low (`rst_b`). All modules synchronously deassert reset.

## AXI requirements
* Data width: 128-bit.
* Bursts: INCR, aligned to 64-byte boundaries by construction.
* Outstanding reads limited to parameter `OUTSTANDING_RD` in `axi_dma.v`.

## Physical integration checklist
1. Instantiate `cop_agent` and `cnn_accel_top` within the Xuantie C908 SoC top.
2. Connect the AXI master ports to the memory interconnect.
3. Map CSRs into the SoC address map (recommended base: `0x8800_0000`).
4. Route the DDR4 DCP and on-chip SRAM IP within Vivado.
5. Include constraints from `hw/constr` in the top-level project.

## Software programming model
1. Enable the COP interface by writing `mxstatus` CSR (`write_mxstatus(0xc1038100);`).
2. Populate DMA descriptors and convolution parameters via CSR writes.
3. Issue the custom instruction intrinsic (`__riscv_xt_conv2d`, etc.).
4. Poll memory or rely on interrupt to observe completion; the instruction
   returns zero on success.

