# Talos v1.0.0 Kernel & Userspace ABI

This document defines the frozen **Talos v1.0.0** hardware interface, virtual memory map, `EL0t` syscall ABI, executable loader rules, and `TalosFS` binary layout.

## 1. Target Hardware & Physical Memory Map

Target platform:

```text
qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 128M
```

Talos runs at `EL1h` with stage-1 identity mapping enabled (`TTBR0_EL1`, 4 KiB granule, 39-bit virtual address space, `T0SZ = 25`, `EPD1 = 1`, 2 MiB L2 block descriptors). `MAIR_EL1 = 0x0000_0000_0000_FF00` configures `Attr0` as Device-nGnRnE (`0x00`) and `Attr1` as Normal Write-Back Write-Allocate Cacheable (`0xFF`, inner-shareable).

| Physical / Virtual Range | Mapping & Permissions | Purpose |
| --- | --- | --- |
| `0x0800_0000`–`0x0800_FFFF` | Device-nGnRnE, `AP[2:1] = 0b00`, `PXN = 1`, `UXN = 1` | GICv2 Distributor (`GICD`) |
| `0x0801_0000`–`0x0801_FFFF` | Device-nGnRnE, `AP[2:1] = 0b00`, `PXN = 1`, `UXN = 1` | GICv2 CPU Interface (`GICC`) |
| `0x0900_0000`–`0x0900_0FFF` | Device-nGnRnE, `AP[2:1] = 0b00`, `PXN = 1`, `UXN = 1` | PL011 UART0 (`115200 8N1`) |
| `0x0a00_0000`–`0x0a00_3FFF` | Device-nGnRnE, `AP[2:1] = 0b00`, `PXN = 1`, `UXN = 1` | VirtIO-MMIO Bus (32 slots × `0x200` stride) |
| `0x4000_0000`–`0x401F_FFFF` | Normal WB, `AP[2:1] = 0b00`, `UXN = 1` | Kernel image (`0x4008_0000`), `.bss`, page tables, and `SP_EL1` stacks |
| `0x4020_0000`–`0x403F_FFFF` | Normal WB, `AP[2:1] = 0b01`, `PXN = 1`, `UXN = 0` | `EL0t` User Arena (2 MiB total; see layout below) |
| `0x4040_0000`–`0x47FF_FFFF` | Normal WB, `AP[2:1] = 0b00`, `UXN = 1` | Kernel-only DRAM |
| `0x4800_0000+` | Unmapped (invalid L2/L1 entries) | Triggers EL1/EL0 Data or Instruction Abort |

### Hardware Interfaces

- **ARM Generic Timer:** EL1 non-secure physical timer (`CNTPCT_EL0`, `CNTP_CTL_EL0`, `CNTP_TVAL_EL0`), GICv2 PPI `30`, configured per online core at `100 Hz`.
- **SMP Inter-Processor Interrupts:** GICv2 SGI `0` via `GICD_SGIR` (`0x0800_0F00`) for reschedule wakeups across cores `0..3`.
- **PSCI Conduit:** `hvc #0` with `CPU_ON = 0xC400_0003`, `SYSTEM_OFF = 0x8400_0008`, and `SYSTEM_RESET = 0x8400_0009`.

### `EL0t` User Arena Layout (`0x4020_0000`–`0x403F_FFFF`)

- `0x4020_0000`–`0x403E_FFFF` (`1984 KiB`): Loadable image region (ELF64 `PT_LOAD` segments or flat `.bin` payloads up to 1 MiB).
- `0x403F_0000`–`0x403F_FFFF` (`64 KiB`): User stack region; initial `SP_EL0 = 0x403FF000`.
- On entry via `eret`, `SPSR_EL1 = 0` (`EL0t`, DAIF unmasked), `x0`–`x30 = 0`, and all 4 per-process file descriptor slots (`0..3`) are reset to closed.

## 2. Frozen `SVC #0` Syscall ABI

User programs invoke kernel services using `svc #0`:

- **Syscall number:** `x8`
- **Arguments:** `x0`–`x5`
- **Return value:** `x0` (`-1` / `0xFFFF_FFFF_FFFF_FFFF` on error or unknown syscall number)
- **Register preservation:** `x1`–`x30` and `SP_EL0` are preserved across `svc #0`; `x0` is overwritten with the syscall return value.
- **Fault isolation:** Non-`SVC` synchronous exceptions from `EL0` (e.g., accessing kernel memory or unmapped addresses) are trapped by `EL1`, logged (`ESR_EL1`, `ELR_EL1`, `FAR_EL1`), and unwound cleanly to the kernel caller with exit code `-1`.

| `x8` | Name | Signature | Behavior & Bounds |
| --- | --- | --- | --- |
| `0` | `SYS_EXIT` | `(code)` -> `!` | Never returns; terminates `EL0t` execution and returns `code` to the kernel caller. |
| `1` | `SYS_WRITE` | `(buf, len)` -> `n \| -1` | Validates `len <= 256` and `[buf, buf + len)` within `[0x4020_0000, 0x4040_0000)` without wrap-around; writes bytes to UART0; returns `len` or `-1`. |
| `2` | `SYS_GETTICKS` | `()` -> `ticks` | Returns Core 0 monotonic `100 Hz` timer tick count. |
| `3` | `SYS_YIELD` | `()` -> `0` | Cooperatively yields the CPU to the scheduler; returns `0`. |
| `4` | `SYS_OPEN` | `(path_ptr)` -> `fd \| -1` | Validates a NUL-terminated path of at most 64 bytes inside `[0x4020_0000, 0x4040_0000)`, resolves it in `TalosFS`, allocates the lowest free FD slot `0..3`, and returns `fd` or `-1` (including `EMFILE` when all 4 slots are open). |
| `5` | `SYS_READ` | `(fd, buf, count)` -> `n \| -1` | Validates open `fd` in `0..3`, `count <= 4096`, and `[buf, buf + count)` within `[0x4020_0000, 0x4040_0000)` without wrap-around; reads up to `min(count, remaining)` bytes, advances offset, and returns bytes read (`0` at EOF) or `-1`. |
| `6` | `SYS_CLOSE` | `(fd)` -> `0 \| -1` | Validates open `fd` in `0..3`, marks the slot free, and returns `0` or `-1`. |
| `7` | `SYS_CPU_ID` | `()` -> `cpu` | Returns executing Cortex-A72 core ID (`MPIDR_EL1 & 0xFF`, `0..3`). |
| `8` | `SYS_SLEEP` | `(ticks)` -> `0` | Sleeps calling task for `ticks` Core 0 timer ticks (`0` yields immediately); returns `0`. |
| `9` | `SYS_BLK_READ` | `(sector, buf)` -> `0 \| -1` | Validates `buf` in `[0x4020_0000, 0x403F_FE00]` and `sector < capacity`; reads a 512-byte VirtIO-Blk sector into `buf`; returns `0` or `-1`. |
| `10` | `SYS_BLK_WRITE` | `(sector, buf)` -> `0 \| -1` | Validates `buf` in `[0x4020_0000, 0x403F_FE00]`, writable media, and `sector < capacity`; writes a 512-byte VirtIO-Blk sector from `buf`; returns `0` or `-1`. |
| `11` | `SYS_GETC` | `()` -> `byte` | Blocks with local IRQs enabled until 1 byte arrives from PL011 UART0; returns `0..255`. |

Any `x8` outside `0..11` returns `-1` (`0xFFFF_FFFF_FFFF_FFFF`).

## 3. Executable Formats

The kernel image dispatcher (`user_exec_image`) inspects the first 4 bytes of an executable (`flags = 1`):

### ELF64 Loader (`src/elf.S`)

Triggered when image size `>= 4` and the first 4 bytes equal `\x7fELF`. The loader validates the full header and all program headers before writing to user RAM:

- **ELF64 header (`Elf64_Ehdr`, 64 bytes):**
  - `e_ident[EI_CLASS] = ELFCLASS64 (2)`
  - `e_ident[EI_DATA] = ELFDATA2LSB (1)`
  - `e_ident[EI_VERSION] = EV_CURRENT (1)`
  - `e_type = ET_EXEC (2)`
  - `e_machine = EM_AARCH64 (183)`
  - `e_version = 1`, `e_ehsize = 64`
  - `e_entry` is 4-byte aligned and within `[0x4020_0000, 0x403F_0000)`
  - `e_phentsize >= 56`, `1 <= e_phnum <= 16`, `e_phoff >= 64`, and the entire program header table fits within the file size
- **Program headers (`PT_LOAD = 1`):**
  - At least one `PT_LOAD` segment must be present
  - `p_filesz <= p_memsz`
  - `[p_offset, p_offset + p_filesz)` lies within the file bounds
  - `[p_vaddr, p_vaddr + p_memsz)` lies strictly within `[0x4020_0000, 0x403F_0000)` (preserving the top 64 KiB for `SP_EL0`)
- **Loading & cache coherency:**
  - Copies `p_filesz` bytes from `file + p_offset` to `p_vaddr`
  - Zero-fills `[p_vaddr + p_filesz, p_vaddr + p_memsz)` (`.bss`)
  - Cleans data cache lines (`dc cvau`, `dsb ish`) and invalidates instruction cache lines (`ic ivau`, `dsb ish`, `isb`) using line sizes from `CTR_EL0`

### Flat Binary Fallback (`user_exec_blob`)

Any executable without the `\x7fELF` header (or shorter than 4 bytes) is treated as a raw AArch64 flat `.bin`:

- Size must satisfy `1 <= size <= 0x0010_0000` (`1 MiB`)
- Copied verbatim to `0x4020_0000`
- Synchronized with `dc cvau`, `ic ivau`, `dsb ish`, and `isb`
- Entered at `ELR_EL1 = 0x4020_0000` with `SP_EL0 = 0x403FF000`

## 4. `TalosFS` On-Image Layout (`src/ramfs.S`)

`TalosFS` is an immutable in-memory filesystem embedded in kernel `.rodata` at symbol `ramfs_table`. It consists of a contiguous array of 32-byte descriptors terminated by a 32-byte all-zero sentinel (`{0, 0, 0, 0}`):

| Offset | Size | Field | Description |
| --- | --- | --- | --- |
| `+0x00` | 8 bytes | `name_ptr` | Pointer to NUL-terminated ASCII filename (`0` marks end-of-table sentinel) |
| `+0x08` | 8 bytes | `data_ptr` | Pointer to immutable file payload bytes |
| `+0x10` | 8 bytes | `size` | Payload length in bytes |
| `+0x18` | 8 bytes | `flags` | Entry type: `0` = regular file (`FILE`), `1` = executable (`EXEC`) |
