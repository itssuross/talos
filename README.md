# Talos

Talos (`itssuross/talos`) is a hobbyist bare-metal ARM64 kernel written entirely in AArch64 assembly (`.S`), with a linker script (`linker.ld`) and a `Makefile`. The kernel uses zero C, zero Rust, and zero external dependencies.

## Target hardware

`qemu-system-aarch64 -M virt -cpu cortex-a72 -m 128M`

| Component | Address or interface |
| --- | --- |
| EL1 kernel load address | `0x4008_0000` |
| PL011 UART0 | `0x0900_0000` |
| GICv2 Distributor | `0x0800_0000` |
| GICv2 CPU Interface | `0x0801_0000` |
| ARM Generic Timer | EL1 non-secure physical timer (`CNTP`), PPI 30, 100 Hz |
| PSCI conduit | `hvc #0` (`SYSTEM_OFF = 0x8400_0008`, `SYSTEM_RESET = 0x8400_0009`) |

## EL1 memory map

Talos enables the MMU and both instruction and data caches before initializing the GIC and timer. At EL1, `TTBR0_EL1` points to a 4 KiB L1 table for the 39-bit virtual address space. Its first two entries each point to a 4 KiB L2 table. Each valid L2 entry maps a 2 MiB block to the same physical address.

| Virtual address range | Translation |
| --- | --- |
| `0x0000_0000`–`0x3FFF_FFFF` | L1[0], all 512 L2 blocks. Device-nGnRnE, EL1 RW (`AP[2:1] = 0b00`), `PXN = 1`, `UXN = 1`. Includes the UART and GIC. |
| `0x4000_0000`–`0x401F_FFFF` | L1[1], L2 entry 0. Kernel DRAM: Normal write-back cacheable, inner-shareable, EL1 RW (`AP[2:1] = 0b00`), `UXN = 1`. |
| `0x4020_0000`–`0x403F_FFFF` | L1[1], L2 entry 1. 2 MiB `EL0t` user arena: Normal write-back cacheable, inner-shareable, EL1/EL0 RW (`AP[2:1] = 0b01`), `PXN = 1`, `UXN = 0`. |
| `0x4040_0000`–`0x47FF_FFFF` | L1[1], L2 entries 2–63. Remaining kernel DRAM: Normal write-back cacheable, inner-shareable, EL1 RW (`AP[2:1] = 0b00`), `UXN = 1`. |
| `0x4800_0000` and above | Unmapped. The remaining 448 entries in the DRAM L2 table and all higher L1 entries are invalid. |

## Prerequisites

On Apple Silicon macOS, install QEMU and the LLVM toolchain with `brew install qemu llvm`. If `ld.lld` is unavailable, install it with `brew install lld`. For the GNU toolchain, use `brew install qemu aarch64-elf-binutils`.

## Build and run

| Command | Result |
| --- | --- |
| `make` | Builds `build/talos.elf` and `build/talos.bin` |
| `make run` | Boots Talos in QEMU with `-nographic` |
| `make test` | Runs scripted shell commands in QEMU and captures their output in `build/test.log` |
| `make LLD=` | Builds using GNU `aarch64-elf-*` binutils |
| `make clean` | Removes `build/` |

## Task scheduler

Talos schedules up to four EL1 tasks in round-robin order. Slot 0 runs the UART shell on the boot stack. Slots 1–3 each have a 4 KiB stack. At boot, `worker-a` and `worker-b` each increment a counter and wait for an interrupt with `wfi`. Only the shell writes to UART0 during normal operation.

Every 100 Hz timer interrupt charges one tick to the running task. The dispatcher sends the GICv2 end-of-interrupt before the scheduler can switch stacks. Both a timer tick and a cooperative yield select the next ready task and call `context_switch`. It saves `x19`–`x30` in a 96-byte frame on the outgoing task’s `SP_EL1` stack, saves that stack pointer in its task control block, and restores the incoming task’s frame. A new task starts in `task_trampoline`, which unmasks IRQs and calls its entry point with its argument. Returning from the entry point frees the slot for reuse.

## EL0t user mode and syscalls

Talos runs isolated `EL0t` payloads inside the 2 MiB user arena (`0x4020_0000`–`0x403F_FFFF`). Before entering user mode, `user_run_demo` copies a position-independent payload to `0x4020_0000`, cleans the data cache (`dc cvau`), and invalidates the instruction cache (`ic ivau`). `user_exec` saves the kernel frame on `SP_EL1`, sets `SP_EL0 = 0x403F_F000`, `ELR_EL1 = 0x4020_0000`, and `SPSR_EL1 = 0` (`EL0t`, IRQs unmasked), clears `x0`–`x30`, and executes `eret`. Lower-EL timer IRQs route through vector slot 9 and return to `EL0t` transparently.

User code invokes the kernel via `SVC #0` with the syscall number in `x8` and the return value in `x0`. Any non-`SVC` synchronous exception from `EL0` (such as a permission fault when accessing kernel memory) logs `ESR_EL1`, `ELR_EL1`, and `FAR_EL1` and unwinds cleanly back to the kernel caller via `user_exit_to_kernel`.

| `x8` | Syscall | Arguments & return |
| --- | --- | --- |
| `0` | `SYS_EXIT` | `x0 = exit_code`. Terminates user execution and returns `exit_code` to the kernel caller. |
| `1` | `SYS_WRITE` | `x0 = buf_ptr`, `x1 = len`. Validates `[buf_ptr, buf_ptr + len)` lies within `[0x4020_0000, 0x4040_0000)` and `len <= 256`, writes bytes to UART0, and returns `len` (or `-1` on invalid bounds). |
| `2` | `SYS_GETTICKS` | Returns `timer_get_ticks()` in `x0`. |
| `3` | `SYS_YIELD` | Calls `sched_yield()` and returns `0` in `x0`. |
| Other | Unknown | Returns `-1` (`0xFFFFFFFFFFFFFFFF`) in `x0`. |

## UART0 shell

Run `make run` and enter commands at the `talos> ` prompt. The PL011 line editor echoes up to 127 printable characters. Enter submits the line, Backspace or Delete erases the last character, and Ctrl+C cancels the line. The 100 Hz timer keeps counting while the shell waits for input.

| Command | Result |
| --- | --- |
| `help` | Lists the built-in commands. |
| `info` | Prints the kernel version, current exception level, CPU affinity register, vector base, counter frequency in Hz, and interrupt masks. |
| `mmu` | Prints `SCTLR_EL1`, `TTBR0_EL1`, `TCR_EL1`, and `MAIR_EL1`, followed by the MMU state. |
| `ticks` | Prints the number of timer interrupts since boot. |
| `uptime` | Prints uptime in seconds to two decimal places and the corresponding tick count. |
| `tasks` | Shows each active task’s ID, state, switch-in count, accrued timer ticks, and name, followed by the worker iteration counts. |
| `yield` | Hands the CPU to the next ready task and prints a confirmation when the shell resumes. |
| `user [fault]` | Runs the `EL0t` user-space demo (`SYS_WRITE`, `SYS_GETTICKS`, `SYS_YIELD`, `SYS_EXIT`). With `fault`, runs an `EL0t` probe that reads kernel memory at `0x4008_0000`, triggers an isolated `EL0` Data Abort, and returns to the shell. |
| `peek <hex_addr>` | Reads a 64-bit word at an 8-byte-aligned address. Use 1–16 hex digits with an optional `0x` or `0X` prefix. For example, `peek 0x40080000` reads the first word of the kernel image. An unmapped address can trigger a data abort. |
| `brk` | Executes `BRK #0x42`, prints the exception register dump, and shuts down. |
| `reboot` | Resets QEMU via PSCI and returns to a fresh shell. |
| `halt` | Powers off via PSCI and exits QEMU. |

## Milestones

- [x] **v0.1.0** — EL1 entry, secondary core parking (`MPIDR_EL1`), `.bss` zeroing, FP/SIMD enable (`CPACR_EL1`), PL011 UART0 TX/RX and 64-bit hex output, and PSCI `SYSTEM_OFF`.
- [x] **v0.2.0** — 16-entry, 2048-byte aligned `VBAR_EL1` exception vector table, IRQ mask controls, and a `BRK #0x42` self-test that dumps the synchronous exception's fault registers, stack pointer, and all 31 general-purpose registers over UART before PSCI shutdown.
- [x] **v0.3.0** — The EL1h IRQ vector saves and restores the interrupted context. The GICv2 dispatcher handles physical timer interrupts on PPI 30, counting each tick and rearming the timer for 10 ms. The v0.3.0 boot test printed the counter frequency and the first ten ticks over UART before PSCI shutdown.
- [x] **v0.4.0** — Interactive UART0 kernel shell with line editing, system inspection, live timer queries, and PSCI reboot and shutdown.
- [x] **v0.5.0** — EL1 stage-1 identity mapping, instruction and data caches, and the `mmu` shell command.
- [x] **v0.6.0** — Four-slot preemptive round-robin scheduler, cooperative yields, per-task stacks, background workers, and the `tasks` and `yield` shell commands.
- [x] **v0.7.0** — Hardware-isolated 2 MiB `EL0t` user arena (`0x4020_0000`–`0x403F_FFFF`), `eret` trampoline with cache coherency, `SVC #0` syscall dispatcher (`SYS_EXIT`, `SYS_WRITE`, `SYS_GETTICKS`, `SYS_YIELD`), Lower-EL fault recovery, and the `user [fault]` shell command.
