# Talos

Talos (`itssuross/talos`) is a hobbyist bare-metal ARM64 kernel written entirely in AArch64 assembly (`.S`), with a linker script (`linker.ld`) and a `Makefile`. The kernel uses zero C, zero Rust, and zero external dependencies.

## Target hardware

`qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M`

| Component | Address or interface |
| --- | --- |
| EL1 kernel load address | `0x4008_0000` |
| PL011 UART0 | `0x0900_0000` |
| GICv2 Distributor | `0x0800_0000` |
| GICv2 CPU Interface | `0x0801_0000` |
| ARM Generic Timer | EL1 non-secure physical timer (`CNTP`), PPI 30, 100 Hz |
| PSCI conduit | `hvc #0` (`CPU_ON = 0xC400_0003`, `SYSTEM_OFF = 0x8400_0008`, `SYSTEM_RESET = 0x8400_0009`) |

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

## Four-core SMP

Core 0 builds the identity-mapped page tables, enables the GICv2 distributor, and starts cores 1–3 with PSCI `CPU_ON` over `hvc #0`. Each secondary enters at `secondary_entry` in `src/boot.S` with a dedicated 4 KiB `SP_EL1` stack. In `src/smp.S` it installs its exception vectors and enables the MMU using the shared tables and registers its pinned idle task before publishing its online flag with a release store. Core 0 waits up to one second for each successfully started core to report online.

Each core enables its banked GICv2 CPU interface, configures PPI 30 in the banked distributor registers, and arms its own 100 Hz physical timer. The IRQ handler increments the core’s slot in `core_ticks[0..3]`. All four cores run the scheduler after a timer interrupt or a reschedule IPI. A secondary executes `wfi` in its idle task when it has no other work.

The PL011 driver takes a shared lock once per `uart_putc` call or whole `uart_puts` string. The spinlocks in `src/spinlock.S` use the ARMv8 exclusive monitor (`ldaxr` and `stxr`), wait with `wfe`, and release with `stlr`. During early single-core boot, the lock operations return immediately while the MMU is off.

## Task scheduler

The shared table contains eight 64-byte task control blocks. Each core tracks its running slot in `current_task[0..3]` and scans the table in round-robin order for the next `READY` task whose affinity permits that core.

| Slots | Task | CPU affinity | EL1 stack |
| --- | --- | --- | --- |
| 0 | `shell` | CPU 0 | Boot stack |
| 1–3 | `idle-1`, `idle-2`, `idle-3` | Matching secondary CPU | 4 KiB per core in `secondary_stacks` |
| 4–7 | Dynamically spawned tasks | Any online CPU (`-1`) | 4 KiB per slot in `task_stacks` |

Every scheduler state transition runs with local IRQs masked and `sched_lock` held. The dispatcher acknowledges a timer interrupt or SGI with the original GICv2 IAR value at end-of-interrupt before scheduling. `context_switch` saves `x19`–`x30` in a 96-byte frame and stores the outgoing stack pointer in its TCB. The lock stays held through the stack switch and is released on the incoming stack. This ensures that another core can only claim the outgoing task after its frame is complete. On first dispatch, `task_trampoline` releases the lock before unmasking IRQs and calling the entry point. Returning from that entry frees the slot under the same lock.

`sched_spawn` publishes a ready task and writes SGI 0 with target mask `0x0e` to `GICD_SGIR` (distributor offset `0xF00`). Cores 1–3 can then dispatch the task immediately. `sched_sleep(n)` records a deadline in core 0 timer ticks. Core 0 marks sleepers ready when their deadlines arrive, and any eligible core can resume them. A zero duration yields. When a pinned sleeper must serve as its own core’s fallback, it can service interrupts while waiting for its deadline.

At boot, `worker-a` and `worker-b` record their executing CPU and sleep for one tick per iteration. When secondaries are online, core 0 gives both workers up to 125 ms in total to record their first secondary execution before it enables its own IRQs. The `tasks` command shows per-CPU execution counts for each worker.

## EL0t user mode, RAMFS, and syscalls

Talos includes a read-only in-memory filesystem (`TalosFS` in `src/ramfs.S`) stored in `.rodata`. `ramfs_table` holds 32-byte entries (`name_ptr`, `data_ptr`, `size`, `flags`, terminated by an all-zero sentinel) housing regular text files (`motd.txt`, `about.txt`) and position-independent flat `EL0t` executables (`hello.bin`, `reader.bin`, `fault.bin`).

Talos runs isolated `EL0t` payloads inside the 2 MiB user arena (`0x4020_0000`–`0x403F_FFFF`). `user_exec_blob` validates a payload size up to 1 MiB (`0x10_0000`), copies it to `0x4020_0000`, cleans the data cache (`dc cvau`), and invalidates the instruction cache (`ic ivau`) with `dsb ish; isb`. `user_exec` saves the kernel frame on `SP_EL1`, resets the 4-slot per-process file descriptor table, sets `SP_EL0 = 0x403F_F000`, `ELR_EL1 = 0x4020_0000`, and `SPSR_EL1 = 0` (`EL0t`, IRQs unmasked), clears `x0`–`x30`, and executes `eret`. Lower-EL timer IRQs route through vector slot 9 and return to `EL0t` transparently.

User code invokes the kernel via `SVC #0` with the syscall number in `x8` and the return value in `x0`. Any non-`SVC` synchronous exception from `EL0` (such as a permission fault when accessing kernel memory) logs `ESR_EL1`, `ELR_EL1`, and `FAR_EL1` and unwinds cleanly back to the kernel caller via `user_exit_to_kernel`.

| `x8` | Syscall | Arguments & return |
| --- | --- | --- |
| `0` | `SYS_EXIT` | `x0 = exit_code`. Terminates user execution and returns `exit_code` to the kernel caller. |
| `1` | `SYS_WRITE` | `x0 = buf_ptr`, `x1 = len`. Validates `[buf_ptr, buf_ptr + len)` lies within `[0x4020_0000, 0x4040_0000)` and `len <= 256`, writes bytes to UART0, and returns `len` (or `-1` on invalid bounds). |
| `2` | `SYS_GETTICKS` | Returns `timer_get_ticks()` in `x0`. |
| `3` | `SYS_YIELD` | Calls `sched_yield()` and returns `0` in `x0`. |
| `4` | `SYS_OPEN` | `x0 = path_ptr`. Validates a NUL-terminated path (up to 64 bytes) inside `[0x4020_0000, 0x4040_0000)`, resolves it via `ramfs_lookup`, allocates the lowest free FD slot (`0`–`3`), and returns the descriptor (or `-1`). |
| `5` | `SYS_READ` | `x0 = fd`, `x1 = buf_ptr`, `x2 = count`. Validates open `fd`, `count <= 4096`, and `[buf_ptr, buf_ptr + count)` within `[0x4020_0000, 0x4040_0000)`, copies up to `min(count, remaining)` bytes, advances the FD offset, and returns bytes read (or `-1`). |
| `6` | `SYS_CLOSE` | `x0 = fd`. Validates open `fd`, releases the descriptor slot, and returns `0` (or `-1`). |
| `7` | `SYS_CPU_ID` | Returns the executing CPU ID (`0`–`3`) in `x0`. |
| `8` | `SYS_SLEEP` | `x0 = ticks`. Sleeps until the tick deadline, or yields when `ticks = 0`. Returns `0` in `x0`. |
| Other | Unknown | Returns `-1` (`0xFFFFFFFFFFFFFFFF`) in `x0`. |

## UART0 shell

Run `make run` and enter commands at the `talos> ` prompt. The PL011 line editor echoes up to 127 printable characters. Enter submits the line, Backspace or Delete erases the last character, and Ctrl+C cancels the line. The 100 Hz timer keeps counting while the shell waits for input.

| Command | Result |
| --- | --- |
| `help` | Lists the built-in commands. |
| `info` | Prints the kernel version, current exception level, CPU affinity register, vector base, counter frequency in Hz, and interrupt masks. |
| `cpuinfo` | Prints the online CPU count and each core’s ID, MPIDR, online state, timer IRQ count, and reschedule IPI count (`SGI_IPI`). |
| `mmu` | Prints `SCTLR_EL1`, `TTBR0_EL1`, `TCR_EL1`, and `MAIR_EL1`, followed by the MMU state. |
| `ticks` | Prints the number of timer interrupts on core 0 since boot. |
| `uptime` | Prints uptime in seconds to two decimal places and the corresponding tick count. |
| `tasks` | Shows each active task’s ID, state, last CPU, affinity, switch-in count, ticks charged by timer or SGI dispatch, and name, followed by per-CPU worker execution counts. |
| `yield` | Hands the CPU to the next ready task and prints a confirmation when the shell resumes. |
| `ls` | Lists all files in `TalosFS` with their type (`FILE` or `EXEC`), byte size, and name. |
| `cat <file>` | Looks up `<file>` in `TalosFS` and prints its contents to UART0. |
| `exec <file>` | Loads an executable (`flags = 1`) from `TalosFS` into the `EL0t` user arena via `user_exec_blob`, runs it, and prints its exit status. |
| `user [fault]` | Launches `hello.bin` (or `fault.bin` with `fault`) from `TalosFS` in `EL0t` to exercise syscalls and hardware fault isolation. |
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
- [x] **v0.8.0** — Pure AArch64 read-only in-memory filesystem (`TalosFS` in `src/ramfs.S`), per-process 4-slot file descriptor table, bounds-checked file syscalls (`SYS_OPEN`, `SYS_READ`, `SYS_CLOSE`), dynamic `EL0t` binary loader (`user_exec_blob`), and the `ls`, `cat`, and `exec` shell commands.
- [x] **v0.9.0** — Four-core Cortex-A72 bring-up via PSCI `CPU_ON`, per-core GICv2 and Generic Timer IRQs, exclusive-monitor UART spinlocks, and the `cpuinfo` shell command.
- [x] **v0.10.0** — Symmetric four-core scheduling across eight slots, locked stack handoff, GICv2 SGI 0 reschedule IPIs, tick-driven sleep, `SYS_CPU_ID` and `SYS_SLEEP`, and per-CPU migration counters.
