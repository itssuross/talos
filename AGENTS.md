# Talos

Talos (`itssuross/talos`) is an MIT-licensed bare-metal AArch64 microkernel written 100% in pure assembly (`src/*.S` and `user/*.S`). It builds via `Makefile`, `linker.ld`, and `user/user.ld` with zero C, Rust, or external dependencies.

## Target Hardware & Memory Map

Emulate with `qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M`. Full ABI contracts live in `docs/ABI.md`.

| Component | Address or Interface |
| --- | --- |
| GICv2 Distributor (`GICD`) | `0x0800_0000`–`0x0800_FFFF` (Device-nGnRnE) |
| GICv2 CPU Interface (`GICC`) | `0x0801_0000`–`0x0801_FFFF` (Device-nGnRnE) |
| PL011 UART0 | `0x0900_0000`–`0x0900_0FFF` (`115200 8N1`) |
| VirtIO-MMIO Bus | `0x0a00_0000`–`0x0a00_3FFF` (32 slots × `0x200` stride) |
| QEMU RAM Base / Kernel Load | `0x4000_0000` / `0x4008_0000` (`EL1`, `AP[2:1] = 0b00`, `UXN = 1`) |
| `EL0t` User Arena | `0x4020_0000`–`0x403F_FFFF` (2 MiB, `AP[2:1] = 0b01`, `PXN = 1`, `UXN = 0`) |
| Kernel DRAM / Unmapped | `0x4040_0000`–`0x47FF_FFFF` (`EL1` only) / `0x4800_0000+` (fault) |
| ARM Generic Timer | `CNTPCT_EL0`, `CNTP_CTL_EL0`, `CNTP_TVAL_EL0`; PPI 30 (100 Hz) |
| PSCI | `hvc #0`; `CPU_ON = 0xC400_0003`, `SYSTEM_OFF = 0x8400_0008`, `SYSTEM_RESET = 0x8400_0009` |

## Assembly & ABI Conventions

- **100% Assembly:** Never create `.c`, `.h`, or `.rs` files.
- **AAPCS64:** Treat `x0`–`x18` as caller-saved and `x19`–`x29` as callee-saved. Preserve `x30` (`lr`) across nested calls and keep `sp` 16-byte aligned at every public call and exception boundary.
- **Frozen `v1.0` ABI:** Never break syscalls `0`–`11` documented in `docs/ABI.md`; new syscalls must be additive (`12+`) and update `docs/ABI.md` + `user/selftest.S`.
- **Minimal Comment Hygiene:** Only write `// ABI:` register-clobber contracts above functions and concise hardware register/bitfield notes. Never write instruction-by-instruction narration.

## Verification & Toolchain Contract

Every code change must build and pass tests with **zero warnings** under both toolchains before tagging or finishing:
1. Clang/LLD: `make -B test`
2. GNU binutils: `make -B LLD= BUILD=/tmp/talos-gnu test && rm -rf /tmp/talos-gnu`
3. Keep all temporary reproducers or scratch files inside `/tmp/talos-*` and delete them before concluding so `git status` remains completely clean.

## Git & GitHub Workflow

- **Atomic 1-File-Per-Commit:** Create or edit one file at a time, stage only that path (`git add <file>`), and commit immediately with a Conventional Commit message (`feat(...)`, `fix(...)`, `test(...)`, `docs(...)`, `build(...)`, `ci(...)`, `chore(...)`) before touching the next file.
- **Safety Boundaries:** Never force-push `main`, rewrite git history, or delete/overwrite existing release tags. Reference resolved issues with `Closes #<n>` in commit bodies.
- **Releases:** Always rebuild fresh `build/talos.elf` and `build/talos.bin` via `make -B` and attach both to GitHub Releases via `gh release create`.
