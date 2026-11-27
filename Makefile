LLVM_PREFIX := $(shell brew --prefix llvm 2>/dev/null)
LLD_PREFIX := $(shell brew --prefix lld 2>/dev/null)
CLANG := $(or $(wildcard $(LLVM_PREFIX)/bin/clang),$(shell command -v clang))
LLD := $(or $(wildcard $(LLVM_PREFIX)/bin/ld.lld),$(wildcard $(LLD_PREFIX)/bin/ld.lld),$(shell command -v ld.lld))
LLVM_OBJCOPY := $(or $(wildcard $(LLVM_PREFIX)/bin/llvm-objcopy),$(shell command -v llvm-objcopy))

BUILD := build
ELF := $(BUILD)/talos.elf
BIN := $(BUILD)/talos.bin
OBJECTS := $(addprefix $(BUILD)/,boot.o uart.o main.o vectors.o exceptions.o)
QEMU ?= qemu-system-aarch64
QEMU_FLAGS ?= -M virt -cpu cortex-a72 -m 128M -nographic

ifneq ($(and $(CLANG),$(LLD),$(LLVM_OBJCOPY)),)
TARGET := --target=aarch64-unknown-none-elf
ASSEMBLE = "$(CLANG)" $(TARGET) -ffreestanding -Wall -Wextra -Werror -Wa,--fatal-warnings -c
LINK = "$(CLANG)" $(TARGET) -nostdlib -ffreestanding -fuse-ld=lld --ld-path="$(LLD)" -Wl,--fatal-warnings,-T,linker.ld
OBJCOPY = "$(LLVM_OBJCOPY)"
else
AS = aarch64-elf-as
LD = aarch64-elf-ld
OBJCOPY = aarch64-elf-objcopy
ASSEMBLE = $(AS) --fatal-warnings
LINK = $(LD) --fatal-warnings -T linker.ld
endif

.PHONY: all run test clean

all: $(ELF) $(BIN)

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: src/%.S | $(BUILD)
	$(ASSEMBLE) $< -o $@

$(ELF): linker.ld $(OBJECTS)
	$(LINK) $(OBJECTS) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

run: all
	$(QEMU) $(QEMU_FLAGS) -serial mon:stdio -kernel $(ELF)

test: all
	@status=0; \
		perl -e 'alarm 5; exec @ARGV' $(QEMU) $(QEMU_FLAGS) -serial stdio -monitor none -kernel $(ELF) </dev/null >$(BUILD)/test.log 2>&1 || status=$$?; \
		cat $(BUILD)/test.log; \
		test "$$status" -eq 0 && \
		grep -q "Talos v" $(BUILD)/test.log && \
		grep -q "Halting via PSCI SYSTEM_OFF" $(BUILD)/test.log

clean:
	rm -rf $(BUILD)
