# Talos

Talos (`itssuross/talos`) is a hobbyist bare-metal ARM64 kernel written entirely in AArch64 assembly (`.S`), with a linker script (`linker.ld`) and a `Makefile`. The kernel uses zero C, zero Rust, and zero external dependencies.

## Target hardware

`qemu-system-aarch64 -M virt -cpu cortex-a72 -m 128M`

| Component | Address or interface |
| --- | --- |
| EL1 kernel load address | `0x4008_0000` |
| PL011 UART0 | `0x0900_0000` |
| PSCI conduit | `hvc #0` (`SYSTEM_OFF = 0x8400_0008`) |

## Prerequisites

On Apple Silicon macOS, install QEMU and the LLVM toolchain with `brew install qemu llvm`. If `ld.lld` is unavailable, install it with `brew install lld`. For the GNU toolchain, use `brew install qemu aarch64-elf-binutils`.

## Build and run

| Command | Result |
| --- | --- |
| `make` | Builds `build/talos.elf` and `build/talos.bin` |
| `make run` | Boots Talos in QEMU with `-nographic` |
| `make LLD=` | Builds using GNU `aarch64-elf-*` binutils |
| `make clean` | Removes `build/` |

## Milestones

- [x] **v0.1.0** — EL1 entry, secondary core parking (`MPIDR_EL1`), `.bss` zeroing, FP/SIMD enable (`CPACR_EL1`), PL011 UART0 TX/RX and 64-bit hex output, and PSCI `SYSTEM_OFF`.
- [ ] **v0.2.0** — `VBAR_EL1` exception vector table, synchronous trap frame dump, and IRQ mask control.
- [ ] **v0.3.0** — GICv2 interrupt controller and ARM Generic Timer tick.
- [ ] **v0.4.0** — Interactive kernel shell over UART0.
