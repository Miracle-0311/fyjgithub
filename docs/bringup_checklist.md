# Bring-up Checklist

1. **Hardware preparation**
   - Program the VU440 board with the generated `cnn_accel.bit`.
   - Confirm power rails and clocks are within tolerance (200 MHz system clock).
   - Verify DDR4 reference design is stable using the vendor memory test.

2. **SoC configuration**
   - Update the Xuantie SoC top RTL to instantiate `cop_agent` and
     `cnn_accel_top` with the correct AXI and COP connections.
   - Map accelerator CSRs into the system bus (default base `0x8800_0000`).
   - Connect the interrupt line to the platform interrupt controller if used.

3. **Firmware setup**
   - Install the Xuantie LLVM toolchain and ensure the custom instruction shared
     libraries (`libcxt-conv2d-compiler.so`, etc.) are on the host.
   - Build the SDK demo under `sw/rtos_demo` by running `make`.
   - Load the resulting ELF through OpenOCD or DebugServer using `gdbinit.r908-cp`.

4. **Validation**
   - Boot the bare-metal RTOS demo and observe UART prints `cnn done` and the
     checksum value.
   - Run the simulation smoke test via `ci/run_sim.sh`.
   - Optionally instrument performance counters via `regs_if` CSRs.

5. **Regression**
   - Integrate the scripts under `ci/` into the CI pipeline to build FPGA images
     and SDK artifacts for each commit.

