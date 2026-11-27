LLVM_PREFIX := $(shell brew --prefix llvm 2>/dev/null)
LLD_PREFIX := $(shell brew --prefix lld 2>/dev/null)
CLANG := $(or $(wildcard $(LLVM_PREFIX)/bin/clang),$(shell command -v clang))
LLD := $(or $(wildcard $(LLVM_PREFIX)/bin/ld.lld),$(wildcard $(LLD_PREFIX)/bin/ld.lld),$(shell command -v ld.lld))
LLVM_OBJCOPY := $(or $(wildcard $(LLVM_PREFIX)/bin/llvm-objcopy),$(shell command -v llvm-objcopy))

BUILD := build
ELF := $(BUILD)/talos.elf
BIN := $(BUILD)/talos.bin
SRCS := src/boot.S src/uart.S src/main.S src/vectors.S src/exceptions.S src/gic.S src/timer.S src/string.S src/shell.S src/mmu.S src/sched.S src/syscall.S
OBJECTS := $(patsubst src/%.S,$(BUILD)/%.o,$(SRCS))
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
		: >$(BUILD)/test.log; \
		( tries=0; until grep -q '^talos> ' $(BUILD)/test.log; do \
			tries=$$((tries + 1)); test $$tries -lt 100 || exit 1; sleep 0.05; \
		  done; sleep 0.15; printf 'help\ninfo\nmmu\nticks\nuptime\nyield\ntasks\npeek 0x40080000\nhalt\n' ) | \
		perl -e 'alarm 5; exec @ARGV' $(QEMU) $(QEMU_FLAGS) -serial stdio -monitor none -kernel $(ELF) >$(BUILD)/test.log 2>&1 || status=$$?; \
		cat $(BUILD)/test.log; \
		test "$$status" -eq 0 && \
		grep -Fq "Talos v0.6.0" $(BUILD)/test.log && \
		grep -q "^talos> help" $(BUILD)/test.log && \
		grep -q "^Commands: .*mmu.*tasks.*yield" $(BUILD)/test.log && \
		grep -q "^CurrentEL: 1" $(BUILD)/test.log && \
		grep -Eq "^SCTLR_EL1: 0x[[:xdigit:]]{16}" $(BUILD)/test.log && \
		grep -Eq "^TTBR0_EL1: 0x[[:xdigit:]]{13}000" $(BUILD)/test.log && \
		grep -Eq "^TCR_EL1  : 0x0000000[0-5]00803519" $(BUILD)/test.log && \
		grep -q "^MAIR_EL1 : 0x000000000000FF00" $(BUILD)/test.log && \
		grep -Fq "MMU State: ENABLED (4KiB granule, 39-bit VA, 2MiB blocks)" $(BUILD)/test.log && \
		grep -q "^Ticks: [0-9]" $(BUILD)/test.log && \
		grep -q "^Uptime: [0-9]" $(BUILD)/test.log && \
		grep -Fq "Yielded CPU to scheduler." $(BUILD)/test.log && \
		grep -Fq "ID  STATE    SWITCHES  TICKS     NAME" $(BUILD)/test.log && \
		grep -Eq "^0 +RUNNING +[1-9][0-9]* +[1-9][0-9]* +shell[[:space:]]*$$" $(BUILD)/test.log && \
		grep -Eq "^1 +READY +[1-9][0-9]* +[1-9][0-9]* +worker-a[[:space:]]*$$" $(BUILD)/test.log && \
		grep -Eq "^2 +READY +[1-9][0-9]* +[1-9][0-9]* +worker-b[[:space:]]*$$" $(BUILD)/test.log && \
		grep -Eq "^worker-a iterations: [1-9][0-9]*" $(BUILD)/test.log && \
		grep -Eq "^worker-b iterations: [1-9][0-9]*" $(BUILD)/test.log && \
		grep -Eq "^0x0000000040080000: 0x[[:xdigit:]]{16}" $(BUILD)/test.log && \
		grep -q "Halting via PSCI SYSTEM_OFF" $(BUILD)/test.log

clean:
	rm -rf $(BUILD)
