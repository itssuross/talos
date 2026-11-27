LLVM_PREFIX := $(shell brew --prefix llvm 2>/dev/null)
LLD_PREFIX := $(shell brew --prefix lld 2>/dev/null)
CLANG := $(or $(wildcard $(LLVM_PREFIX)/bin/clang),$(shell command -v clang))
LLD := $(or $(wildcard $(LLVM_PREFIX)/bin/ld.lld),$(wildcard $(LLD_PREFIX)/bin/ld.lld),$(shell command -v ld.lld))
LLVM_OBJCOPY := $(or $(wildcard $(LLVM_PREFIX)/bin/llvm-objcopy),$(shell command -v llvm-objcopy))

BUILD := build
OBJECTS := $(addprefix $(BUILD)/,boot.o uart.o main.o)

ifneq ($(and $(CLANG),$(LLD),$(LLVM_OBJCOPY)),)
TARGET := --target=aarch64-unknown-none-elf
ASSEMBLE = "$(CLANG)" $(TARGET) -ffreestanding -Wall -Wextra -Werror -Wa,--fatal-warnings -c
LINK = "$(CLANG)" $(TARGET) -nostdlib -ffreestanding -fuse-ld=lld --ld-path="$(LLD)" -Wl,--fatal-warnings,-T,linker.ld
OBJCOPY = "$(LLVM_OBJCOPY)"
else
ASSEMBLE = aarch64-elf-as --fatal-warnings
LINK = aarch64-elf-ld --fatal-warnings -T linker.ld
OBJCOPY = aarch64-elf-objcopy
endif

.PHONY: all run clean

all: $(BUILD)/talos.elf $(BUILD)/talos.bin

$(BUILD):
	mkdir -p $@

$(BUILD)/%.o: src/%.S | $(BUILD)
	$(ASSEMBLE) $< -o $@

$(BUILD)/talos.elf: linker.ld $(OBJECTS)
	$(LINK) $(OBJECTS) -o $@

$(BUILD)/talos.bin: $(BUILD)/talos.elf
	$(OBJCOPY) -O binary $< $@

run: all
	qemu-system-aarch64 -M virt -cpu cortex-a72 -m 128M -nographic -serial mon:stdio -kernel $(BUILD)/talos.elf

clean:
	rm -rf $(BUILD)
