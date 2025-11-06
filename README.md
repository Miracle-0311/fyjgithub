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
