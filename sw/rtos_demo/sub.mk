CC ?= riscv64-unknown-elf-gcc
OBJDUMP ?= riscv64-unknown-elf-objdump
CFLAGS += -march=rv64gcv -mabi=lp64d -mcmodel=medany \
          -miconfig=$(CURDIR)/../dsa/libcxt-conv2d-compiler.so
OBJDUMPFLAGS += --disassembler-options=plugin=$(CURDIR)/../dsa/libcxt-conv2d-disassembler.so
