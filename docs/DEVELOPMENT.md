# Talos Development, Debugging & Forking Guide

This guide is for developers debugging Talos under QEMU, writing standalone `EL0t` user programs, contributing upstream, or forking Talos as an MIT-licensed bare-metal AArch64 base kernel.

---

## 1. Debugging with GDB / LLDB & QEMU

QEMU includes a built-in GDB stub that exposes all four Cortex-A72 cores as debugger threads without modifying the kernel.

### Launching QEMU Halted at Reset

First build `build/talos.elf` and ensure `build/disk.img` exists:

```sh
make -B all build/disk.img
```

Start QEMU paused at `_start` (`-S`) with the GDB server listening on TCP port `1234` (`-s`):

```sh
qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -smp 4 -m 128M \
  -nographic -serial mon:stdio \
  -drive file=build/disk.img,format=raw,if=none,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -kernel build/talos.elf \
  -s -S
```

### Attaching `gdb-multiarch` / `aarch64-elf-gdb`

In a second terminal, launch GDB with the kernel ELF symbols and attach to `localhost:1234`:

```sh
# Linux / WSL2:
gdb-multiarch build/talos.elf

# macOS (Homebrew: brew install aarch64-elf-gdb):
aarch64-elf-gdb build/talos.elf
```

Inside GDB:

```gdb
(gdb) target remote localhost:1234
(gdb) b kmain
(gdb) c
```

> **Using LLDB (macOS / Linux):**
> ```sh
> lldb build/talos.elf -o "gdb-remote localhost:1234"
> ```
> Then use `b kmain`, `c`, `register read`, and `thread list`.

### Inspecting `EL1` / `EL0` System Registers

QEMU's AArch64 GDB stub exposes architectural system registers directly:

```gdb
# Exception level, fault syndrome, faulting PC and address
(gdb) info registers CurrentEL ESR_EL1 ELR_EL1 FAR_EL1 SPSR_EL1

# Stage-1 MMU configuration
(gdb) info registers SCTLR_EL1 TTBR0_EL1 TCR_EL1 MAIR_EL1

# Per-core identity, stacks, and interrupt masks
(gdb) info registers MPIDR_EL1 VBAR_EL1 SP_EL0 DAIF
```

You can also inspect raw memory in the `EL0t` arena or kernel tables:

```gdb
# Inspect L1 page table entries (mmu_l1)
(gdb) x/4gx &mmu_l1

# Inspect all 8 scheduler TCBs (64 bytes each)
(gdb) x/64gx &tcb_table

# Load symbols for a standalone EL0t user program currently mapped at 0x40200000
(gdb) add-symbol-file build/user/selftest.elf 0x40200000
```

### Setting Breakpoints Across 4 SMP Cores

Each Cortex-A72 core appears as a GDB thread (`1`–`4`):

```gdb
# List all 4 CPUs and their current PCs
(gdb) info threads

# Switch to Core 1 (thread 2) and inspect its registers
(gdb) thread 2
(gdb) info registers pc sp MPIDR_EL1

# Trace secondary bring-up, syscalls, or scheduler switches on any core
(gdb) b secondary_entry
(gdb) b el0_sync_dispatch
(gdb) b syscall_dispatch
(gdb) b context_switch
(gdb) c
```

> **Tip:** Software breakpoints (`b`) patch RAM at the virtual address, so breakpoints set inside the `EL0t` user arena (`0x4020_0000`–`0x403F_FFFF`) will be overwritten when `exec` runs `.Lzero_user_arena` and loads a new image. Use hardware breakpoints (`hb *0x40200000`) or break at `user_exec` first and step over `eret` into `EL0t`.

---

## 2. Writing Standalone `EL0t` User Programs (`user/*.S`)

Talos loads standalone `ELF64` (`ET_EXEC`, `EM_AARCH64`) binaries from `TalosFS` into the hardware-isolated 2 MiB `EL0t` arena (`0x4020_0000`–`0x403F_FFFF`). See [`docs/ABI.md`](ABI.md) for the complete 12-syscall contract.

### Step 1: Create `user/hello_user.S`

Place `_start` in `.section .text.entry, "ax"` so `user/user.ld` maps it at `0x4020_0000`, invoke kernel services via `svc #0` with the syscall number in `x8`, and always terminate via `SYS_EXIT` (`x8 = 0`):

```asm
.equ SYS_EXIT,  0
.equ SYS_WRITE, 1

.section .text.entry, "ax"
.global _start
.type _start, %function

// ABI: EL0t entry with 16-byte aligned SP_EL0. Exits via SYS_EXIT.
_start:
    adr x0, .Lmsg
    mov x1, #(.Lmsg_end - .Lmsg)
    mov x8, #SYS_WRITE
    svc #0

    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0
.size _start, . - _start

.section .rodata, "a"
.Lmsg:
    .ascii "hello_user.elf: greetings from EL0t!\n"
.Lmsg_end:
```

### Step 2: Register the Target in `Makefile`

Add `$(BUILD)/user/hello_user.elf` to `USER_ELFS` in `Makefile`:

```makefile
USER_ELFS := $(BUILD)/user/echo.elf $(BUILD)/user/sysinfo.elf $(BUILD)/user/selftest.elf $(BUILD)/user/hello_user.elf
```

The existing pattern rules automatically assemble `user/%.S` and link `$(BUILD)/user/%.elf` against `user/user.ld` (which sets `. = 0x40200000`, defines `PT_LOAD` `text` (`PF_R|PF_X`) and `data` (`PF_R|PF_W`), and passes `--build-id=none`).

### Step 3: Embed the ELF in `src/ramfs.S`

`Makefile` assembles `src/ramfs.S` with `-I$(BUILD)`, so `.incbin "user/hello_user.elf"` resolves directly to `build/user/hello_user.elf`.

1. Add a 32-byte entry to `ramfs_table` (before the `.quad 0, 0, 0, 0` sentinel) with `flags = 1` (`EXEC`):

   ```asm
       .quad .Lname_hello_user, .Lfile_hello_user_start, .Lfile_hello_user_end - .Lfile_hello_user_start, 1
   ```

2. Add the filename label and `.incbin` block:

   ```asm
   .Lname_hello_user:
       .asciz "hello_user.elf"
   ```

   ```asm
   .balign 8
   .Lfile_hello_user_start:
       .incbin "user/hello_user.elf"
   .Lfile_hello_user_end:
   ```

### Step 4: Build and Run

```sh
make -B run
```

At the `talos> ` prompt:

```text
talos> ls
talos> exec hello_user.elf
hello_user.elf: greetings from EL0t!
Exited with code: 0
```

### Userland Rules to Keep in Mind

- All `PT_LOAD` segments must fit strictly inside `[0x4020_0000, 0x403F_0000)` and must not overlap; the top 64 KiB (`0x403F_0000`–`0x403F_FFFF`) is reserved for `SP_EL0` (initialized to `0x403F_F000`).
- Entry point `e_entry` must be 4-byte aligned and located inside an executable (`PF_X`) `PT_LOAD` segment.
- Pointer arguments to `SYS_WRITE`, `SYS_READ`, `SYS_OPEN`, `SYS_BLK_READ`, and `SYS_BLK_WRITE` must lie strictly inside `[0x4020_0000, 0x403F_FFFF]` (and the entire buffer range must fit within `[0x4020_0000, 0x4040_0000)`).
- Any unmapped or privileged memory access in `EL0t` is caught by `el0_sync_dispatch` and cleanly returns `-1` to the kernel caller without panicking the kernel.

---

## 3. Forking Talos as a Base Kernel

Talos is licensed under the **MIT License** ([`LICENSE`](../LICENSE)) and structured so low-level hardware bring-up is cleanly separated from OS policy:

| Layer | Files | Responsibility |
| --- | --- | --- |
| **Hardware Mechanism** | `src/boot.S`, `src/vectors.S`, `src/exceptions.S`, `src/mmu.S`, `src/gic.S`, `src/timer.S`, `src/spinlock.S`, `src/smp.S`, `src/virtio_blk.S`, `src/uart.S` | EL2->EL1h boot, vector table, 2-level MMU, GICv2, 100 Hz timers, spinlocks, 4-core SMP, VirtIO-Blk DMA, PL011 UART0 |
| **OS Policy & Services** | `src/main.S`, `src/sched.S`, `src/syscall.S`, `src/elf.S`, `src/ramfs.S`, `src/string.S`, `src/shell.S` | Task policy, syscall ABI, ELF64 loader, `TalosFS`, interactive shell |
| **Userspace** | `user/user.ld`, `user/*.S` | Standalone `EL0t` ELF64 programs built against `docs/ABI.md` |

Common ways to build on a fork of Talos:
- **Replace the shell:** Swap the `bl shell_run` call in `src/main.S` with your own init routine or auto-launch an `EL0t` `init.elf` directly from `TalosFS` via `ramfs_lookup` + `user_exec_image`.
- **Add persistent filesystems:** Layer a FAT, ext2, or custom block filesystem over `blk_read_sector` / `blk_write_sector` (`src/virtio_blk.S`) while keeping the same `SYS_OPEN` / `SYS_READ` / `SYS_CLOSE` interface.
- **Write C, Rust, or Zig `EL0t` userspace:** While upstream Talos remains 100% pure assembly, forks can compile freestanding `aarch64-unknown-none-elf` user binaries in C, Rust, or Zig linked with `user/user.ld` (`0x4020_0000`) and invoke the frozen 12-syscall `SVC #0` ABI (`docs/ABI.md`) with a thin inline-assembly syscall wrapper.
- **Expand virtual memory:** Replace the 2 MiB `mmu_l2_ram` user block with per-process L3 4 KiB page tables (`TTBR0_EL1` switching + ASIDs) for multi-process address spaces.

---

## 4. Repository Conventions & Verification

Upstream contributions to `itssuross/talos` must adhere to the following standards (also defined in [`AGENTS.md`](../AGENTS.md)):

### Assembly & Style Conventions

- **100% Pure AArch64 Assembly:** Zero `.c`, `.h`, or `.rs` files in the repository.
- **AAPCS64 Calling Convention:** Treat `x0`–`x18` as caller-saved and `x19`–`x29` as callee-saved; observe any platform reservation of `x18`; preserve `x30` across nested calls; maintain 16-byte `sp` alignment at all public call boundaries.
- **Minimal Comments:** Use `// ABI:` register-clobber contracts above functions and brief hardware register/bitfield notes only. Avoid instruction-by-instruction narration.
- **Zero Warnings:** Assembler and linker warnings are fatal (`-Wall -Wextra -Werror -Wa,--fatal-warnings -Wl,--fatal-warnings` on Clang/LLD; `--fatal-warnings` on GNU binutils).

### Atomic 1-File-Per-Commit Git Hygiene

Every commit on `main` modifies or creates **exactly one file**, staged explicitly with `git add <file>` and committed immediately using a Conventional Commit message (`feat(...)`, `fix(...)`, `docs(...)`, `build(...)`, `test(...)`, `chore(...)`).

### Dual-Toolchain Zero-Warning Verification

Before submitting or tagging any release, verify both toolchains pass `make test` with zero warnings and exit code `0`:

```sh
# 1. Clang / LLD build + full QEMU smoke test
make -B test

# 2. GNU aarch64-elf-* binutils build + full QEMU smoke test (isolated BUILD dir)
make -B LLD= BUILD=/tmp/talos-gnu test
rm -rf /tmp/talos-gnu
```

*(On Linux/WSL2 with `binutils-aarch64-linux-gnu`, pass `AS=aarch64-linux-gnu-as LD=aarch64-linux-gnu-ld OBJCOPY=aarch64-linux-gnu-objcopy` alongside `LLD=`.)*

### The 18-Check `selftest.elf` Adversarial ABI Suite (`user/selftest.S`)

`make test` boots Talos in QEMU, exercises all subsystems (timer, SMP migration across CPUs `0`–`3`, MMU, `TalosFS`, VirtIO-Blk persistence across PSCI warm `reboot`, and `EL0t` fault isolation), and runs `exec selftest.elf`, which verifies 18 adversarial ABI invariants:

| Check | Invariant Verified |
| --- | --- |
| `1` | Unknown syscall (`x8 = 99`) returns `-1` |
| `2` | Out-of-range syscall (`x8 = -1`) returns `-1` |
| `3` | `SYS_WRITE` rejects kernel address (`0x4008_0000`) |
| `4` | `SYS_WRITE` rejects buffer straddling `0x4040_0000` (`0x403F_FFF0`, `len = 32`) |
| `5` | `SYS_WRITE` rejects wrapping length (`len = -16`) |
| `6` | `SYS_OPEN` rejects kernel address (`0x4008_0000`) |
| `7` | `SYS_OPEN` returns `-1` for nonexistent `missing.txt` |
| `8` | `SYS_OPEN` allocates FDs `0`–`3` sequentially and rejects a 5th concurrent open (`EMFILE`) |
| `9` | `SYS_READ` rejects kernel destination buffer (`0x4008_0000`) |
| `10` | `SYS_READ` rejects out-of-range FD (`7`) |
| `11` | `SYS_CLOSE` releases FDs `0`–`3` and rejects double-closing FD `0` |
| `12` | `SYS_BLK_READ` rejects kernel destination buffer (`0x4008_0000`) |
| `13` | `SYS_BLK_WRITE` rejects 512-byte buffer straddling `0x4040_0000` (`0x403F_FF00`) |
| `14` | `SYS_BLK_READ` rejects out-of-bounds sector (`0xFFFF_FFFF`) |
| `15` | `SYS_WRITE` rejects zero-length pointer at `0x4040_0000` |
| `16` | `SYS_READ` rejects zero-length pointer at `0x4040_0000` on an open FD |
| `17` | Full 2 MiB `EL0t` arena zeroing before `exec` (`SP_EL0` stack frame and `0x4030_0000` are zero on entry) |
| `18` | `SYS_CPU_ID` returns `0`–`3`; `SYS_SLEEP(0)` yields; `SYS_SLEEP(1)` and `SYS_SLEEP(2)` advance Core `0` ticks accordingly |
