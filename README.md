# Xuantie C908 CNN Accelerator

This repository hosts a reference implementation of an INT8 CNN hardware
accelerator targeting the Xuantie C908 processor with the COP interface enabled.
It contains FPGA RTL, build scripts, a simulation scaffold, and a bare-metal SDK
example demonstrating the custom instructions.

## Repository layout
Refer to the `repo/` tree described in the project brief:

- `hw/rtl` – synthesizable Verilog modules for the accelerator.
- `hw/ip` – placeholders for required Xilinx IP cores.
- `hw/build` – Vivado project generation scripts.
- `hw/sim` – behavioural testbench assets.
- `sw/dsa` – custom instruction metadata and intrinsics.
- `sw/rtos_demo` – bare-metal demo application.
- `docs/` – integration guide and bring-up checklist.
- `ci/` – helper scripts for building bitstreams, simulations, and SDK.

## Quick start
1. Install Vivado 2022.2 and the Xuantie LLVM toolchain.
2. Populate `hw/ip/` with the vendor XCI/DCP files.
3. Run `ci/run_vivado.sh` to generate a bitstream.
4. Build the SDK demo via `ci/build_sdk.sh` and deploy it using the provided
   GDB script.

For detailed integration steps see `docs/integration.md`.

## COP instruction summary

The `cop_agent_cnn` module implements the following 32-bit instruction map on
`pad_cop_req_insn[31:0]`:

| Opcode | Mnemonic | Description |
| --- | --- | --- |
| `4'h1` | `OP_LOADW` | Stream eight 32-bit words (256 bits) of filter data into the weight scratchpad at `weight_addr = insn[27:16]`. |
| `4'h2` | `OP_LOADI` | Stream eight 32-bit words of input feature map data into the IFM scratchpad at `ifmap_addr = insn[27:16]`. |
| `4'h3` | `OP_START` | Start a convolution run with `width=insn[27:20]`, `height=insn[19:12]`, `in_ch=insn[11:8]`, `out_ch=insn[7:4]`, `stride=insn[3:0]`. |
| `4'h4` | `OP_READO` | Request a 64-bit slice of the pooled feature map at `ofmap_addr = insn[27:16]`. |
| `4'h5` | `OP_STAT` | Return accelerator status: `resp[0] = done`, `resp[1] = busy`, `resp[63:32] = last_ofmap_addr`. |

All load commands enqueue a 256-bit data block into an internal FIFO (depth 16).
FIFO head entries are forwarded to the accelerator with one block accepted per
cycle because `load*_rdy` is hardwired high inside `cnn_accel_top`.

## Scratchpad addressing

`cnn_accel_top` stores weights, IFMs, and OFMs as byte-addressable arrays. Each
`OP_LOAD*` and `OP_READO` address selects 32 consecutive bytes; i.e. the byte
offset is `{addr,5'b0}`. The compute core expects channel-major tensors packed
with one 8-bit element per byte.

## Status and readback

- `OP_STAT` responses mirror the accelerator's sticky `done` flag and real-time
  `busy` flag. The `last_ofmap_addr` field returns the most recent write pointer
  aligned to 32-byte blocks.
- `OP_READO` responses deliver the least-significant 64 bits of the 256-bit
  scratchpad line. Multiple consecutive `OP_READO` requests are required to read
  a complete 256-bit block.

## Testbench hook

An optional behavioural testbench `cnn_accel_tb.v` can drive the COP interface
using helper tasks `send_req()` and `recv_resp()` to validate the datapath
against pre-computed golden vectors.
