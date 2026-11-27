# Talos

Talos (`itssuross/talos`) is a bare-metal AArch64 kernel written entirely in assembly. Kernel code belongs in `.S` files. The project uses `linker.ld` and `Makefile` to build without C, Rust, or external libraries.

## Target hardware

Use `qemu-system-aarch64 -M virt -cpu cortex-a72 -m 128M`.

| Component | Address or interface |
| --- | --- |
| QEMU RAM base | `0x4000_0000` |
| EL1 kernel load address in RAM | `0x4008_0000` |
| PL011 UART0 | `0x0900_0000` |
| GICv2 Distributor | `0x0800_0000` |
| GICv2 CPU Interface | `0x0801_0000` |
| ARM Generic Timer | `CNTPCT_EL0`, `CNTP_CTL_EL0`, `CNTP_TVAL_EL0`; PPI 30 |
| PSCI | `hvc #0`; `SYSTEM_OFF = 0x8400_0008`, `SYSTEM_RESET = 0x8400_0009` |

## Assembly conventions

- Follow AAPCS64. Treat `x0`–`x18` as caller-saved and `x19`–`x29` as callee-saved. Observe any platform reservation of `x18`. Preserve the return address when making a nested call that returns.
- Keep `sp` 16-byte aligned at public call boundaries.
- Use only `// ABI:` register-clobber contracts above functions and concise hardware register or bitfield annotations. Omit instruction-by-instruction narration.
- Enable assembler and linker warnings and keep builds warning-free.

## Git workflow

Initialize the repository on `main` if needed. Create or edit one file at a time, stage only that path with `git add <file>`, and commit it immediately with its Conventional Commit message before starting the next file. Every commit must contain exactly one file.
