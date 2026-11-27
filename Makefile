LLVM_PREFIX := $(shell brew --prefix llvm 2>/dev/null)
LLD_PREFIX := $(shell brew --prefix lld 2>/dev/null)
CLANG := $(or $(wildcard $(LLVM_PREFIX)/bin/clang),$(shell command -v clang))
LLD := $(or $(wildcard $(LLVM_PREFIX)/bin/ld.lld),$(wildcard $(LLD_PREFIX)/bin/ld.lld),$(shell command -v ld.lld))
LLVM_OBJCOPY := $(or $(wildcard $(LLVM_PREFIX)/bin/llvm-objcopy),$(shell command -v llvm-objcopy))

BUILD := build
ELF := $(BUILD)/talos.elf
BIN := $(BUILD)/talos.bin
DISK := $(BUILD)/disk.img
SRCS := src/boot.S src/uart.S src/main.S src/vectors.S src/exceptions.S src/gic.S src/timer.S src/string.S src/shell.S src/mmu.S src/sched.S src/syscall.S src/ramfs.S src/spinlock.S src/smp.S src/virtio_blk.S
OBJECTS := $(patsubst src/%.S,$(BUILD)/%.o,$(SRCS))
QEMU ?= qemu-system-aarch64
QEMU_FLAGS ?= -M virt -cpu cortex-a72 -smp 4 -m 128M -nographic -serial mon:stdio -drive file=$(DISK),format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0

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

$(DISK): | $(BUILD)
	test -e $@ || dd if=/dev/zero of=$@ bs=512 count=128 2>/dev/null

run: all $(DISK)
	$(QEMU) $(QEMU_FLAGS) -kernel $(ELF)

test: all $(DISK)
	@status=0; \
		: >$(BUILD)/test.log; \
		( tries=0; until grep -q '^talos> ' $(BUILD)/test.log; do \
			tries=$$((tries + 1)); test $$tries -lt 100 || exit 1; sleep 0.05; \
		  done; sleep 0.15; printf 'help\ninfo\ncpuinfo\nmmu\nticks\nuptime\nls\ncat motd.txt\nexec reader.bin\nexec hello.bin\nexec fault.bin\nuser\nuser fault\nyield\ntasks\npeek 0x40080000\nblkinfo\nblkwrite 0 TalosDiskOK\nblkread 0\nexec blktest.bin\nhalt\n' ) | \
		perl -e 'alarm 5; exec @ARGV' $(QEMU) $(QEMU_FLAGS) -kernel $(ELF) >$(BUILD)/test.log 2>&1 || status=$$?; \
		cat $(BUILD)/test.log; \
		test "$$status" -eq 0 && \
		grep -Fq "Talos v0.11.0" $(BUILD)/test.log && \
		grep -q "^talos> help" $(BUILD)/test.log && \
		grep -q "^Commands: .*cpuinfo.*ls.*cat <file>.*exec <file>.*user \[fault\]" $(BUILD)/test.log && \
		grep -q "^CurrentEL: 1" $(BUILD)/test.log && \
		grep -q "^Online CPUs: 4 / 4" $(BUILD)/test.log && \
		grep -Fq "CPU  MPIDR               STATE    IRQ_TICKS  SGI_IPI" $(BUILD)/test.log && \
		for cpu in 0 1 2 3; do \
			sgi=0; test "$$cpu" -eq 0 || sgi='[1-9][0-9]*'; \
			grep -Eq "^$$cpu +0x000000008000000$$cpu +ONLINE +[1-9][0-9]* +$$sgi[[:space:]]*$$" $(BUILD)/test.log || exit 1; \
		done && \
		grep -Eq "^SCTLR_EL1: 0x[[:xdigit:]]{16}" $(BUILD)/test.log && \
		grep -Eq "^TTBR0_EL1: 0x[[:xdigit:]]{13}000" $(BUILD)/test.log && \
		grep -Eq "^TCR_EL1  : 0x0000000[0-5]00803519" $(BUILD)/test.log && \
		grep -q "^MAIR_EL1 : 0x000000000000FF00" $(BUILD)/test.log && \
		grep -Fq "MMU State: ENABLED (4KiB granule, 39-bit VA, 2MiB blocks)" $(BUILD)/test.log && \
		grep -q "^Ticks: [0-9]" $(BUILD)/test.log && \
		grep -q "^Uptime: [0-9]" $(BUILD)/test.log && \
		grep -Fq "TYPE  SIZE      NAME" $(BUILD)/test.log && \
		grep -q "motd.txt" $(BUILD)/test.log && \
		grep -q "Welcome to TalosFS" $(BUILD)/test.log && \
		test "$$(grep -Fc 'Welcome to TalosFS' $(BUILD)/test.log)" -ge 2 && \
		grep -q "hello.bin: running in EL0t via exec!" $(BUILD)/test.log && \
		grep -Fq "Exited with code: 0" $(BUILD)/test.log && \
		grep -Fq "Exited with code: -1" $(BUILD)/test.log && \
		grep -Fq "EL0t user process exited with code: 0" $(BUILD)/test.log && \
		grep -Eq "^\[EL0 fault\] ESR_EL1=0x000000009[23][[:xdigit:]]{6} ELR_EL1=0x0000000040200004 FAR_EL1=0x0000000040080000" $(BUILD)/test.log && \
		grep -q "EL0t fault isolated; returned to shell." $(BUILD)/test.log && \
		grep -Fq "Yielded CPU to scheduler." $(BUILD)/test.log && \
		grep -Fq "ID  STATE     CPU  AFF   SWITCHES  TICKS     NAME" $(BUILD)/test.log && \
		grep -Eq "^0 +RUNNING +0 +0 +[1-9][0-9]* +[1-9][0-9]* +shell[[:space:]]*$$" $(BUILD)/test.log && \
		for cpu in 1 2 3; do \
			grep -Eq "^$$cpu +(READY|RUNNING) +$$cpu +$$cpu +[1-9][0-9]* +[0-9]+ +idle-$$cpu[[:space:]]*$$" $(BUILD)/test.log || exit 1; \
		done && \
		for worker in a b; do \
			slot=4; test "$$worker" = a || slot=5; \
			grep -Eq "^$$slot +(READY|RUNNING|SLEEPING) +[0-3] +ANY +[1-9][0-9]* +[0-9]+ +worker-$$worker[[:space:]]*$$" $(BUILD)/test.log || exit 1; \
			awk -v name="worker-$$worker" '{ sub(/\r$$/, "") } $$1 == name && NF == 5 { \
				cpus = 0; for (i = 2; i <= 5; i++) if ($$i + 0 > 0) cpus++; \
				if (cpus >= 2) migrated = 1; \
			} END { exit !migrated }' $(BUILD)/test.log || exit 1; \
		done && \
		grep -Eq "^0x0000000040080000: 0x[[:xdigit:]]{16}" $(BUILD)/test.log && \
		grep -q "^VirtIO-Blk MMIO" $(BUILD)/test.log && \
		grep -Fq "128 sectors (64 KiB)  Mode: RW" $(BUILD)/test.log && \
		grep -Fq "Wrote sector 0." $(BUILD)/test.log && \
		grep -q "^0x00: 0x736944736F6C6154" $(BUILD)/test.log && \
		grep -q "^0x08: 0x00000000004B4F6B" $(BUILD)/test.log && \
		grep -Fq "blktest.bin: VirtIO-Blk EL0 read/write verified!" $(BUILD)/test.log && \
		grep -q "Halting via PSCI SYSTEM_OFF" $(BUILD)/test.log

clean:
	rm -rf $(BUILD)
