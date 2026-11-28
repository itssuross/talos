# Talos

**Talos** (`itssuross/talos`) is a bare-metal AArch64 microkernel written **100% in pure ARM64 assembly (`.S`)** with zero C, zero Rust, and zero external libraries. Targeting QEMU's 4-core Cortex-A72 `virt` platform, it boots from `EL2` into `EL1h`, brings up stage-1 virtual memory, symmetric 4-core SMP scheduling, persistent VirtIO-Blk storage, an embedded `TalosFS` RAMFS, and a hardware-isolated `EL0t` ELF64 execution environment—all licensed under the **MIT License**.

### Highlights

- **100% Pure AArch64 Assembly:** Every kernel subsystem and standalone user binary is hand-written `.S`, built cleanly with zero warnings on both Clang/LLD and GNU `aarch64-elf-*` binutils.
- **4-Core Cortex-A72 SMP:** PSCI `CPU_ON` bring-up, per-core banked GICv2 interfaces, 100 Hz ARM Generic Timers (`PPI 30`), `SGI 0` reschedule IPIs, exclusive-monitor spinlocks, and an 8-slot symmetric round-robin scheduler.
- **Stage-1 EL1 MMU Isolation:** 4 KiB granule, 39-bit identity-mapped VA space (`T0SZ = 25`), 2 MiB blocks, and a hardware-enforced 2 MiB `EL0t` user arena (`0x4020_0000`–`0x403F_FFFF`, `AP = EL1/EL0 RW`, `PXN = 1`, `UXN = 0`).
- **VirtIO-Blk Persistent Storage:** Auto-detects Modern (`v2`) and Legacy (`v1`) VirtIO-MMIO block devices over an 8-entry split virtqueue with DMA memory barriers and warm-reboot persistence.
- **Frozen v1.0 ABI & ELF64 Loader:** Bounds-checked `ELF64` (`ET_EXEC`, `EM_AARCH64`) loader with full 2 MiB arena zeroing, D/I cache coherency, 12 frozen `SVC #0` syscalls, and an 18-check adversarial `EL0t` self-test suite (`selftest.elf`).
- **MIT Licensed & Fork-Ready:** Clean separation between hardware bring-up and OS policy, designed for systems learning, experimentation, and custom userlands.

---

## 30-Second Quick Start

### Boot a Prebuilt Release Binary

Download `talos.elf` from [GitHub Releases](https://github.com/itssuross/talos/releases) and boot in QEMU:

```sh
qemu-img create -f raw disk.img 64K
qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -smp 4 -m 128M \
  -nographic -serial mon:stdio \
  -drive file=disk.img,format=raw,if=none,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -kernel talos.elf
```

Type `help`, `cpuinfo`, `exec selftest.elf`, or `halt` at the `talos> ` prompt (or press `Ctrl+A` then `X` to exit QEMU).

### Build & Verify from Source

```sh
git clone https://github.com/itssuross/talos.git
cd talos
make -B test   # Zero-warning build + full QEMU smoke & 18/18 ABI regression test
make run       # Interactive PL011 UART0 shell with persistent build/disk.img
```

For full installation instructions on **Windows**, **macOS**, **Linux**, and **BSD**, see [`docs/SETUP.md`](docs/SETUP.md).

---

## Documentation Index

| Guide | Audience & Contents |
| --- | --- |
| [**Setup & Cross-Platform Guide**](docs/SETUP.md) | Prebuilt QEMU quick start; installation and build guides for **Windows** (PowerShell + WSL2), **macOS**, **Linux** (Debian/Ubuntu, Fedora/RHEL, Arch), and **BSD** (`FreeBSD`, `OpenBSD`, `NetBSD`); `Makefile` variables; and a full 20-command shell walkthrough. |
| [**Kernel Architecture**](docs/ARCHITECTURE.md) | Under-the-hood internals: `EL2`->`EL1h` boot flow, 2048-byte `VBAR_EL1` vectors, stage-1 L1/L2 page tables, 4-core SMP bring-up, `sched_lock` handoff, VirtIO-Blk split virtqueues, `TalosFS`, ELF64 cache maintenance, and the module dependency map. |
| [**Frozen v1.0 Kernel & Userspace ABI**](docs/ABI.md) | Authoritative hardware memory map, `EL0t` user arena layout, all 12 `SVC #0` syscalls with exact pointer-bounds contracts, ELF64/flat-binary loader rules, and `TalosFS` 32-byte entry format. |
| [**Development, Debugging & Forking**](docs/DEVELOPMENT.md) | QEMU + GDB/LLDB multi-core debugging, writing standalone `EL0t` assembly programs (`user/*.S`), forking Talos as a base kernel (including C/Rust/Zig userlands), AAPCS64/commit conventions, and the 18-check `selftest.elf` suite. |

---

## Target Hardware & Build Targets

Target machine: `qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M`

| Component | Address / Interface |
| --- | --- |
| EL1 kernel load address | `0x4008_0000` (128 MiB DRAM: `0x4000_0000`–`0x47FF_FFFF`) |
| `EL0t` user arena | `0x4020_0000`–`0x403F_FFFF` (1984 KiB image + 64 KiB `SP_EL0` stack) |
| VirtIO-MMIO bus | `0x0A00_0000`–`0x0A00_3E00` (32 slots, `0x200` stride) |
| PL011 UART0 | `0x0900_0000` (`115200 8N1`) |
| GICv2 Distributor / CPU Interface | `0x0800_0000` / `0x0801_0000` (`PPI 30`, `SGI 0`) |
| ARM Generic Timer & PSCI | `CNTP` at `100 Hz` per core; PSCI `hvc #0` (`CPU_ON`, `SYSTEM_OFF`, `SYSTEM_RESET`) |

| Make Command | Result |
| --- | --- |
| `make` / `make -B` | Builds `build/talos.elf`, `build/talos.bin`, and embedded `build/user/*.elf` binaries (Clang/LLD) |
| `make run` | Boots Talos in QEMU with serial console and persistent 64 KiB `build/disk.img` |
| `make test` | Runs automated QEMU smoke suite + `18/18` `selftest.elf` checks + warm `reboot` persistence test |
| `make -B LLD= BUILD=/tmp/talos-gnu test` | Verifies zero-warning build and smoke test with GNU `aarch64-elf-*` binutils |
| `make clean` | Removes `build/` |

---

## Architecture Overview (`v1.0.2`)

| File | Responsibility |
| --- | --- |
| `linker.ld` | Kernel linker script (`0x4008_0000`, 16 KiB boot `.stack`, `.bss` bounds) |
| `src/boot.S` | `EL2`->`EL1h` drop, `.bss` zeroing, FP/SIMD enable, `secondary_entry` (`secondary_stacks`) |
| `src/main.S` | Boot initialization pipeline, SMP background workers (`worker-a`, `worker-b`), `v1.0.2` banner |
| `src/vectors.S` | 16-entry, 2048-byte aligned `VBAR_EL1` vector table and 272-byte trap frames |
| `src/exceptions.S` | IRQ / `EL0` sync dispatch, EL1 register dump panic handler, PSCI `SYSTEM_OFF` / `SYSTEM_RESET` |
| `src/mmu.S` | Stage-1 EL1 identity page tables (`mmu_l1`, `mmu_l2_dev`, `mmu_l2_ram`) and `EL0t` isolation |
| `src/gic.S` | GICv2 distributor, per-core CPU interfaces, `PPI 30` routing, and `SGI 0` IPIs |
| `src/timer.S` | Per-core 100 Hz ARM Generic Timer (`CNTP`) driver and monotonic `core_ticks[0..3]` |
| `src/spinlock.S` | Pre-MMU-safe ARMv8 exclusive-monitor (`ldaxr`/`stxr`/`stlr`) spinlocks |
| `src/smp.S` | 4-core Cortex-A72 bring-up via PSCI `CPU_ON`, online tracking, and SGI counters |
| `src/sched.S` | 8-slot symmetric SMP round-robin scheduler, locked `context_switch`, and tick-driven sleep |
| `src/syscall.S` | `EL0t` `eret` trampoline, 12 frozen `SVC #0` syscalls, 4-slot FD table, arena wipe & image dispatch |
| `src/elf.S` | Bounds-checked ELF64 `ET_EXEC` loader (`PT_LOAD`, `.bss` zeroing, D/I cache coherency) |
| `src/ramfs.S` | Read-only in-memory `TalosFS` (`ramfs_table`, text files, flat `.bin`, `.incbin` ELF64 images) |
| `src/virtio_blk.S` | Modern v2 and Legacy v1 VirtIO-MMIO block driver with 8-entry split virtqueue DMA |
| `src/uart.S` | Spinlock-protected PL011 UART0 TX/RX, decimal, and 64-bit hex formatting |
| `src/string.S` | String comparison, whitespace skipping, and decimal/hex `u64` parsers |
| `src/shell.S` | Interactive UART0 line editor and 20 built-in shell commands |
| `user/user.ld` | Standalone `EL0t` ELF64 linker script (`0x4020_0000`) |
| `user/echo.S` | Interactive `EL0t` stdin echo ELF64 binary (`SYS_GETC`, `SYS_WRITE`, `SYS_EXIT`) |
| `user/sysinfo.S` | `EL0t` ELF64 `.bss` zeroing, `SYS_CPU_ID`, and `SYS_GETTICKS` verification binary |
| `user/selftest.S` | 18-check adversarial `EL0t` ABI, bounds, arena-zeroing, FD, VirtIO-Blk, and sleep regression suite |

---

## Milestones & Roadmap

- [x] **v0.1.0 – v0.4.0** — `EL2`->`EL1h` boot, PL011 UART0, 2048-byte `VBAR_EL1` vectors, GICv2 + 100 Hz Generic Timer (`PPI 30`), PSCI power control, and interactive kernel shell.
- [x] **v0.5.0 – v0.8.0** — Stage-1 EL1 MMU (4 KiB granule, 39-bit VA, 2 MiB blocks), preemptive scheduler, hardware-isolated `EL0t` user arena, `SVC #0` syscalls, and `TalosFS` RAMFS.
- [x] **v0.9.0 – v0.12.0** — 4-core Cortex-A72 SMP with `SGI 0` IPIs and symmetric scheduling, Modern/Legacy VirtIO-Blk split virtqueue DMA, bounds-checked ELF64 `ET_EXEC` loader, and blocking `SYS_GETC`.
- [x] **v1.0.0** — Frozen ABI specification ([`docs/ABI.md`](docs/ABI.md)), `selftest.elf` adversarial ABI suite, `version` command, warm `reboot` persistence verification, and dual-toolchain Clang/LLD + GNU binutils builds.
- [x] **v1.0.1** — MIT license ([`LICENSE`](LICENSE)), security & ABI hardening fixes (`sched_sleep` 64-bit wrap-around protection, `elf64_load` `PF_X` entry containment and non-overlapping segments, full 2 MiB arena zeroing before `exec`, and zero-length `0x4040_0000` rejection), and 18/18 `selftest.elf` checks.
- [x] **v1.0.2** — Publication-grade documentation suite: cross-platform setup guide ([`docs/SETUP.md`](docs/SETUP.md)), kernel architecture reference ([`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)), developer/GDB/forking guide ([`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)), and revamped front page.
- [ ] **v1.1.0 (Planned)** — Per-process 4 KiB L3 page tables with `TTBR0_EL1` ASID switching and interrupt-driven PL011 UART RX ring buffer.
- [ ] **v2.0.0 (Planned)** — Concurrent multi-process `EL0t` execution, writable VirtIO-Blk filesystem layer, and inter-process message passing.

---

## License

Talos is licensed under the **MIT License**. See [`LICENSE`](LICENSE) for details.
