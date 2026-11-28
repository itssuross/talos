# Talos Setup & Cross-Platform Guide

This guide covers running prebuilt Talos binaries in QEMU, installing toolchains and building from source on **Windows**, **macOS**, **Linux**, and **BSD** (`FreeBSD`, `OpenBSD`, `NetBSD`), and navigating the interactive PL011 UART0 kernel shell.

---

## 1. Quick Start (Run Prebuilt Release Binaries Without Building)

You only need `qemu-system-aarch64` (and `qemu-img` if you want persistent VirtIO-Blk storage) to boot Talos.

1. Download `talos.elf` (or raw `talos.bin`) from the [GitHub Releases](https://github.com/itssuross/talos/releases) page.
2. Create a 64 KiB (128 × 512-byte sectors) raw disk image:

   ```sh
   qemu-img create -f raw disk.img 64K
   ```

3. Boot Talos on a 4-core Cortex-A72 `virt` machine with VirtIO-Blk attached:

   ```sh
   qemu-system-aarch64 \
     -M virt -cpu cortex-a72 -smp 4 -m 128M \
     -nographic -serial mon:stdio \
     -drive file=disk.img,format=raw,if=none,id=hd0 \
     -device virtio-blk-device,drive=hd0 \
     -kernel talos.elf
   ```

   > **Tip (`talos.bin`):** `talos.elf` is the recommended boot artifact because QEMU reads its entry point (`0x4008_0000`) directly from the ELF header. You can also pass `-kernel talos.bin` on `qemu-system-aarch64 -M virt`, which loads raw images at `0x4008_0000`.

4. **Booting without a disk attached:** Omit the `-drive` and `-device` flags. Talos boots normally into the interactive shell, and `blkinfo` reports `VirtIO-Blk: not attached`:

   ```sh
   qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M -nographic -serial mon:stdio -kernel talos.elf
   ```

5. **Exiting QEMU cleanly:**
   - Inside the Talos shell, type `halt` to power off via PSCI `SYSTEM_OFF` (`0x8400_0008`).
   - From anywhere (including if a program is waiting on input), press **`Ctrl+A`** then **`X`** to terminate QEMU immediately.

---

## 2. Platform-by-Platform Installation & Build Instructions

Talos compiles with **zero C, zero Rust, and zero external libraries**. The `Makefile` auto-detects `clang`, `ld.lld`, and `llvm-objcopy` (targeting `--target=aarch64-unknown-none-elf`), and falls back to GNU binutils (`aarch64-elf-as`, `aarch64-elf-ld`, `aarch64-elf-objcopy`) when `LLD=` is passed.

> **Note on `make test`:** The automated smoke test (`make test`) uses `perl`, `awk`, `grep`, and `dd` in addition to `qemu-system-aarch64`.

### Windows (x86_64 & ARM64)

#### Option A: Run Prebuilt `talos.elf` Natively in PowerShell

1. Install QEMU via WinGet:

   ```powershell
   winget install -e --id SoftwareFreedomConservancy.QEMU
   ```

2. Open a new PowerShell window (or refresh `PATH` in your current session so `C:\Program Files\qemu` is visible):

   ```powershell
   $env:Path += ";C:\Program Files\qemu"
   ```

3. Create a 64 KiB raw disk image and boot `talos.elf`:

   ```powershell
   qemu-img create -f raw disk.img 64K
   qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M `
     -nographic -serial mon:stdio `
     -drive file=disk.img,format=raw,if=none,id=hd0 `
     -device virtio-blk-device,drive=hd0 `
     -kernel talos.elf
   ```

#### Option B: Build & Test from Source via WSL2 Ubuntu

The `Makefile` relies on a POSIX shell, GNU Make, and Perl, so WSL2 Ubuntu is the recommended Windows development environment.

1. Inside WSL2 Ubuntu, install the Clang/LLD toolchain and QEMU:

   ```sh
   sudo apt update && sudo apt install -y git make clang lld llvm qemu-system-arm perl
   ```

   *(Optional)* Install GNU AArch64 binutils if you also want to verify GNU assembler/linker builds:

   ```sh
   sudo apt install -y binutils-aarch64-linux-gnu
   ```

2. Clone, build, test, and run:

   ```sh
   git clone https://github.com/itssuross/talos.git
   cd talos
   make -B test
   make run
   ```

   To build and test with GNU `aarch64-linux-gnu-*` binutils in WSL2:

   ```sh
   make -B LLD= AS=aarch64-linux-gnu-as LD=aarch64-linux-gnu-ld OBJCOPY=aarch64-linux-gnu-objcopy BUILD=/tmp/talos-gnu test
   ```

---

### macOS (Apple Silicon & Intel)

1. Install LLVM, LLD, and QEMU via [Homebrew](https://brew.sh/):

   ```sh
   brew install llvm lld qemu
   ```

   *(Optional)* Install bare-metal GNU AArch64 binutils for dual-toolchain verification:

   ```sh
   brew install aarch64-elf-binutils
   ```

2. Homebrew installs `llvm` keg-only. The `Makefile` automatically discovers `$(brew --prefix llvm)/bin` and `$(brew --prefix lld)/bin`, or you can expose LLVM tools directly in your shell:

   ```sh
   export PATH="$(brew --prefix llvm)/bin:$PATH"
   ```

3. Clone, verify, and boot:

   ```sh
   git clone https://github.com/itssuross/talos.git
   cd talos
   make -B test
   make run
   ```

4. *(Optional)* Verify the GNU `aarch64-elf-*` build in a separate build directory:

   ```sh
   make -B LLD= BUILD=/tmp/talos-gnu test
   ```

---

### Linux (Debian/Ubuntu, Fedora/RHEL, Arch Linux)

#### Debian / Ubuntu

```sh
sudo apt update && sudo apt install -y git make clang lld llvm qemu-system-arm perl
# Optional GNU AArch64 binutils:
sudo apt install -y binutils-aarch64-linux-gnu
```

#### Fedora / RHEL

```sh
sudo dnf install -y git make clang lld llvm qemu-system-aarch64 perl
# Optional GNU AArch64 binutils:
sudo dnf install -y binutils-aarch64-linux-gnu
```

#### Arch Linux

```sh
sudo pacman -S --needed git make clang lld llvm qemu-system-aarch64 perl
# Optional GNU AArch64 binutils:
sudo pacman -S --needed aarch64-linux-gnu-binutils
```

#### Build, Test, and Run (Linux)

```sh
git clone https://github.com/itssuross/talos.git
cd talos

# Clang / LLD build and smoke test
make -B test

# Interactive session
make run
```

To build with GNU binutils on Linux (passing `aarch64-linux-gnu-*` if `aarch64-elf-*` is not installed):

```sh
# If aarch64-elf-{as,ld,objcopy} is on PATH:
make -B LLD= BUILD=/tmp/talos-gnu test

# If using distro binutils-aarch64-linux-gnu:
make -B LLD= AS=aarch64-linux-gnu-as LD=aarch64-linux-gnu-ld OBJCOPY=aarch64-linux-gnu-objcopy BUILD=/tmp/talos-gnu test
```

---

### BSD (`FreeBSD`, `OpenBSD`, `NetBSD`)

The Talos `Makefile` uses GNU Make syntax (`$(or ...)`, `$(and ...)`, `:=`, and order-only prerequisites), so use **`gmake`** instead of the base BSD `make`.

#### FreeBSD

```sh
sudo pkg install -y git gmake llvm20 qemu perl5
```

FreeBSD installs versioned LLVM binaries (`clang20`, `ld.lld20`, `llvm-objcopy20`) under `/usr/local/bin` (and unversioned wrappers in `/usr/local/llvm20/bin`). Add `/usr/local/llvm20/bin` to `PATH` before invoking `gmake`:

```sh
export PATH="/usr/local/llvm20/bin:$PATH"
git clone https://github.com/itssuross/talos.git
cd talos
gmake -B test
gmake run
```

#### OpenBSD

```sh
doas pkg_add git gmake llvm qemu
```

Ensure `/usr/local/bin` precedes `/usr/bin` if needed so `clang`, `ld.lld`, and `llvm-objcopy` from ports are selected, then build with `gmake`:

```sh
export PATH="/usr/local/bin:$PATH"
git clone https://github.com/itssuross/talos.git
cd talos
gmake -B test
gmake run
```

#### NetBSD

Configure `PKG_PATH` (or `pkgin`) for your NetBSD release and architecture if not already set, for example:

```sh
export PKG_PATH="https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/$(uname -m)/$(uname -r | cut -d_ -f1)/All"
```

Install dependencies with `pkgin` and build with `gmake`:

```sh
sudo pkgin -y install git gmake clang lld qemu perl
git clone https://github.com/itssuross/talos.git
cd talos
gmake -B test
gmake run
```

---

## 3. Useful `Makefile` Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `BUILD` | `build` | Output directory for objects, `talos.elf`, `talos.bin`, `disk.img`, and `test.log` |
| `DISK` | `$(BUILD)/disk.img` | Path to the 64 KiB raw VirtIO-Blk disk image (auto-created if missing) |
| `QEMU` | `qemu-system-aarch64` | QEMU binary path |
| `QEMU_FLAGS` | `-M virt -cpu cortex-a72 -smp 4 -m 128M -nographic -serial mon:stdio -drive file=$(DISK),format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0` | Flags passed to QEMU for `run` and `test` |
| `LLD` | Auto-detected `ld.lld` | Pass `LLD=` to force the GNU binutils toolchain fallback |
| `AS`, `LD`, `OBJCOPY` | `aarch64-elf-{as,ld,objcopy}` (when `LLD=`) | Override GNU tool names (e.g., `aarch64-linux-gnu-*`) |

---

## 4. Interactive Shell Walkthrough

Talos boots into a PL011 UART0 shell (`talos> `) on Core `0`. The line editor accepts up to **543 characters** (544-byte buffer including NUL terminator), supports `Backspace`/`Delete` to erase, `Enter` to execute, and `Ctrl+C` to cancel the current line. Background SMP workers (`worker-a`, `worker-b`) and 100 Hz timer ticks continue running while the shell waits for input.

### Built-In Command Reference (20 Commands)

| Command | Description |
| --- | --- |
| `help` | Lists all 20 built-in shell commands. |
| `version` | Prints the `Talos v1.0.2 (aarch64-virt)` release banner and frozen ABI v1.0 subsystem summary. |
| `info` | Displays `CurrentEL`, `MPIDR_EL1`, `VBAR_EL1`, `CNTFRQ_EL0` (Hz), and `DAIF` interrupt masks. |
| `cpuinfo` | Displays online CPU count (`4 / 4`) and per-core `MPIDR`, online state, timer `IRQ_TICKS`, and `SGI_IPI` count. |
| `mmu` | Prints `SCTLR_EL1`, `TTBR0_EL1`, `TCR_EL1`, `MAIR_EL1`, and the stage-1 MMU state. |
| `ticks` | Prints Core `0` monotonic 100 Hz timer ticks since boot. |
| `uptime` | Prints formatted uptime in seconds (`SS.CCs`) and tick count. |
| `tasks` | Lists all active scheduler TCB slots (`ID`, `STATE`, `CPU`, `AFF`, `SWITCHES`, `TICKS`, `NAME`) plus per-CPU `worker-a` and `worker-b` execution counts. |
| `yield` | Voluntarily yields Core `0` to the scheduler (`sched_yield`) and reports when the shell resumes. |
| `ls` | Lists all files embedded in `TalosFS` (`FILE` or `EXEC`, byte size, and filename). |
| `cat <file>` | Prints the raw contents of `<file>` from `TalosFS` to UART0. |
| `exec <file>` | Zeroes the 2 MiB `EL0t` user arena, loads an `EXEC` image (ELF64 or flat `.bin`), runs it in `EL0t`, and prints `Exited with code: <n>`. |
| `user [fault]` | Runs `hello.bin` (no argument) or `fault.bin` (`user fault`, which attempts to read kernel memory at `0x4008_0000` and demonstrates isolated `EL0` fault recovery). |
| `blkinfo` | Prints the VirtIO-Blk MMIO base address, transport version (`1` or `2`), capacity in sectors/KiB, and `RW`/`RO` mode. |
| `blkread <sec>` | Reads a 512-byte sector (decimal or `0x`-prefixed hex) and dumps its first 64 bytes as eight 64-bit little-endian hex words. |
| `blkwrite <sec> <text>` | Writes up to 511 ASCII bytes into `<sec>`, zero-filling the remainder of the 512-byte sector. |
| `peek <hex_addr>` | Reads and prints the 64-bit little-endian word at an 8-byte-aligned hexadecimal address (e.g., `peek 0x40080000`). Reading unmapped memory triggers a kernel Data Abort. |
| `brk` | Executes `BRK #0x42` at `EL1h` to test the kernel exception dumper and halts via PSCI `SYSTEM_OFF`. |
| `reboot` | Warm-reboots QEMU via PSCI `SYSTEM_RESET` (`0x8400_0009`). VirtIO-Blk disk writes persist across reboot. |
| `halt` | Cleanly shuts down QEMU via PSCI `SYSTEM_OFF` (`0x8400_0008`). |

### Sample Interactive Session

```text
Talos v1.0.2 (aarch64-virt)
Type 'help' for available commands.
talos> version
Talos v1.0.2 (aarch64-virt) - Pure AArch64 Assembly Microkernel
ABI: v1.0 (12 syscalls, EL1 MMU 4KiB/39-bit, GICv2, 4-core SMP, VirtIO-Blk, ELF64)
talos> cpuinfo
Online CPUs: 4 / 4
CPU  MPIDR               STATE    IRQ_TICKS  SGI_IPI
0    0x0000000080000000  ONLINE   42         0
1    0x0000000080000001  ONLINE   42         2
2    0x0000000080000002  ONLINE   42         2
3    0x0000000080000003  ONLINE   42         2
talos> mmu
SCTLR_EL1: 0x0000000030D01805
TTBR0_EL1: 0x000000004008B000
TCR_EL1  : 0x0000000500803519
MAIR_EL1 : 0x000000000000FF00
MMU State: ENABLED (4KiB granule, 39-bit VA, 2MiB blocks)
talos> ls
TYPE  SIZE      NAME
FILE  47        motd.txt
FILE  72        about.txt
EXEC  81        hello.bin
EXEC  129       reader.bin
EXEC  20        fault.bin
EXEC  253       blktest.bin
EXEC  ...       echo.elf
EXEC  ...       sysinfo.elf
EXEC  ...       selftest.elf
talos> cat motd.txt
Welcome to TalosFS (100% pure AArch64 RAMFS)!
talos> exec selftest.elf
selftest.elf: 18/18 adversarial ABI checks passed!
Exited with code: 0
talos> user fault
Launching EL0t fault probe (reading kernel 0x40080000)...
[EL0 fault] ESR_EL1=0x0000000092000007 ELR_EL1=0x0000000040200004 FAR_EL1=0x0000000040080000
EL0t fault isolated; returned to shell.
talos> blkinfo
VirtIO-Blk MMIO: 0x000000000A003E00  Version: 2
Capacity: 128 sectors (64 KiB)  Mode: RW
talos> blkwrite 0 TalosDiskOK
Wrote sector 0.
talos> blkread 0
0x00: 0x736944736F6C6154
0x08: 0x00000000004B4F6B
0x10: 0x0000000000000000
0x18: 0x0000000000000000
0x20: 0x0000000000000000
0x28: 0x0000000000000000
0x30: 0x0000000000000000
0x38: 0x0000000000000000
talos> tasks
ID  STATE     CPU  AFF   SWITCHES  TICKS     NAME
0   RUNNING   0    0     12        45        shell
1   RUNNING   1    1     28        30        idle-1
2   RUNNING   2    2     26        31        idle-2
3   RUNNING   3    3     25        32        idle-3
4   SLEEPING  2    ANY   38        14        worker-a
5   SLEEPING  1    ANY   37        13        worker-b
WORKER    CPU0      CPU1      CPU2      CPU3
worker-a  0         12        14        12
worker-b  0         13        12        12
talos> peek 0x40080000
0x0000000040080000: 0xD5034FDF...
talos> halt
Halting via PSCI SYSTEM_OFF...
```
