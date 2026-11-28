# Talos Kernel Architecture

This document explains how Talos (`v1.0.2`) operates internally across every subsystem—from cold reset on Core `0` to stage-1 MMU isolation, symmetric 4-core Cortex-A72 scheduling, VirtIO-Blk split virtqueues, and `EL0t` ELF64 execution. Every address, register value, and symbol name corresponds directly to the pure AArch64 assembly sources in `src/` and `user/`.

For the frozen external contract (syscall numbers, pointer-bounds rules, and binary headers), see [`docs/ABI.md`](ABI.md).

---

## 1. Boot & Exception Level Transitions (`src/boot.S`, `src/vectors.S`, `src/exceptions.S`)

### Cold Reset on Core `0` (`_start`)

QEMU loads `talos.elf` at physical RAM address `0x4008_0000` (`linker.ld`) and enters `_start` in `.text.boot`:

1. **Interrupt masking & primary selection:** `_start` immediately masks all asynchronous exceptions (`msr daifset, #0xf`) and checks `MPIDR_EL1` affinity bits (`0x00FF_00FF_FFFF`). Any non-zero core that enters `_start` directly is parked in a low-power `.Lpark` (`wfe`) loop until Core `0` explicitly boots it via PSCI `CPU_ON`.
2. **`EL2` -> `EL1h` drop:** `_start` inspects `CurrentEL` (`cmp x0, #0x8`, i.e., `EL2`). If entered at `EL2`:
   - Writes `HCR_EL2 = (1 << 31)` (`RW = 1`) so `EL1` executes in AArch64 state.
   - Writes `SPSR_EL2 = 0x3c5` (`D`, `A`, `I`, `F` masked; `M[3:0] = 0b0101` = `EL1h`).
   - Sets `ELR_EL2 = .Lel1_entry` and executes `eret`.
3. **EL1 architectural setup (`.Lel1_entry`):**
   - Enables FP/SIMD access by setting `CPACR_EL1.FPEN = 0b11` (`#(3 << 20)`), followed by `isb`.
   - Selects `SP_EL1` (`msr spsel, #1; isb`) and initializes `sp` to `__stack_top` (the top of the 16 KiB `.stack` section in `linker.ld`).
   - Zeroes `[__bss_start, __bss_end)` in 16-byte `stp xzr, xzr` strides.
   - Clears `x29` and `x30` to terminate frame backtraces and branches to `kmain` (`src/main.S`).

### Kernel Initialization Pipeline (`src/main.S`)

`kmain` brings subsystems online in strict dependency order with IRQs masked on Core `0`:

```text
uart_init -> exceptions_init -> mmu_init -> blk_init -> gic_init -> timer_init
  -> sched_init -> smp_init -> sched_spawn(worker-a, worker-b)
  -> await secondary worker hits (<= 125 ms) -> print banner -> irq_enable -> shell_run
```

If `shell_run` ever returns, `kmain` branches to `psci_system_off`.

### Exception Vector Table (`src/vectors.S`)

`exceptions_init` loads `VBAR_EL1` with `vectors`, a 2048-byte aligned table containing 16 entries of 128 bytes each (`0x000`–`0x780`):

| Offset | Slot | Source & Exception Type | Handler Path |
| --- | --- | --- | --- |
| `0x000`–`0x180` | `0`–`3` | Current EL with `SP0` (`EL1t`) Sync / IRQ / FIQ / SError | `.Lexception_common` -> `panic_exception` |
| `0x200` | `4` | Current EL with `SPx` (`EL1h`) Synchronous | `.Lexception_common` -> `panic_exception` |
| `0x280` | `5` | Current EL with `SPx` (`EL1h`) IRQ | `.Lirq_common` -> `irq_dispatch` |
| `0x300`–`0x380` | `6`–`7` | Current EL with `SPx` (`EL1h`) FIQ / SError | `.Lexception_common` -> `panic_exception` |
| `0x400` | `8` | Lower EL (AArch64 / `EL0t`) Synchronous | `.Lel0_sync` -> `el0_sync_dispatch` |
| `0x480` | `9` | Lower EL (AArch64 / `EL0t`) IRQ | `.Lirq_common` -> `irq_dispatch` |
| `0x500`–`0x780` | `10`–`15` | Lower EL AArch64 FIQ/SError & Lower EL AArch32 | `.Lexception_common` -> `panic_exception` |

Every active stub allocates a **272-byte trap frame** on `SP_EL1`:

```text
+0x000 .. +0x0EF : x0  .. x29  (30 × 8 bytes)
+0x0F0           : x30 (LR)
+0x0F8           : original SP_EL1 (panic) or SP_EL0 (EL0 sync)
+0x100           : ELR_EL1
+0x108           : SPSR_EL1
```

### Synchronous `ESR_EL1.EC` Decoding & Fault Isolation (`src/exceptions.S`)

- **Lower-EL Synchronous (`el0_sync_dispatch`):** Extracts `ESR_EL1.EC` (`ubfx x1, x20, #26, #6`).
  - `EC == 0x15` (`SVC` instruction from AArch64): routes to `syscall_dispatch` (`src/syscall.S`), which updates `[frame + 0]` (`x0`) with the return value and returns cleanly to `.Lel0_sync` -> `eret`.
  - Any other `EC` (for example, `0x24` Data Abort from a lower EL when `fault.bin` reads `0x4008_0000`): prints `[EL0 fault] ESR_EL1=... ELR_EL1=... FAR_EL1=...` and unwinds cleanly back to the kernel `user_exec` caller via `user_exit_to_kernel(-1)` without crashing the kernel.
- **EL1 Fatal Faults (`panic_exception`):** Dumps the vector name, `ESR_EL1`, `ELR_EL1`, `FAR_EL1`, `SPSR_EL1`, `SP`, and all 31 general-purpose registers `x00`–`x30`, then shuts down cleanly via `psci_system_off`.

### PSCI `HVC #0` Power Management

Talos communicates with QEMU's EL2/EL3 PSCI firmware conduit using `hvc #0`:

| Function | `x0` Function ID | Arguments | Call Site |
| --- | --- | --- | --- |
| `CPU_ON` (SMC64) | `0xC400_0003` | `x1 = target MPIDR`, `x2 = secondary_entry`, `x3 = context ID` | `smp_init` (`src/smp.S`) |
| `SYSTEM_OFF` | `0x8400_0008` | `x1..x3 = 0` | `psci_system_off` (`src/exceptions.S`) |
| `SYSTEM_RESET` | `0x8400_0009` | `x1..x3 = 0` | `psci_system_reset` (`src/exceptions.S`) |

---

## 2. Stage-1 EL1 MMU & User Arena Isolation (`src/mmu.S`)

Talos uses a 2-level identity-mapped stage-1 translation scheme rooted in `TTBR0_EL1`, with three 4 KiB-aligned tables allocated in `.bss`: `mmu_l1`, `mmu_l2_dev`, and `mmu_l2_ram`.

### Translation Control & Memory Attributes

- **`MAIR_EL1 = 0x0000_0000_0000_FF00`:**
  - `Attr0 = 0x00`: Device-nGnRnE (non-gathering, non-reordering, no early write acknowledgement) for MMIO peripherals.
  - `Attr1 = 0xFF`: Normal memory, Inner/Outer Write-Back Write-Allocate Cacheable for DRAM.
- **`TCR_EL1 = 0x0080_3519 | (IPS << 32)`:**
  - `T0SZ = 25` (`39`-bit virtual address space, `512 GiB` L1 table).
  - `TG0 = 0b00` (`4 KiB` granule; each L2 block maps `2 MiB`).
  - `IRGN0 = 0b01`, `ORGN0 = 0b01` (WBWA table walks), `SH0 = 0b11` (Inner Shareable).
  - `EPD1 = 1` (`TTBR1_EL1` translation walks disabled).
  - `IPS = min(ID_AA64MMFR0_EL1.PARange, 5)` (capped at 48-bit physical address space).
- **Activation (`mmu_init_secondary`):** Loads `MAIR_EL1`, `TCR_EL1`, `TTBR0_EL1 = mmu_l1`, executes `dsb ish; tlbi vmalle1; dsb ish; isb`, and sets `SCTLR_EL1` bits `M` (bit `0`, MMU), `C` (bit `2`, D-cache), and `I` (bit `12`, I-cache) followed by `isb`.

### L1/L2 Descriptor Layout & Hardware Isolation

```text
mmu_l1 (4 KiB, 512 × 1 GiB entries)
 ├── L1[0] -> mmu_l2_dev | 0x3  (0x0000_0000 – 0x3FFF_FFFF)
 │     └── 512 × 2 MiB blocks: 0x0060_0000_0000_0401 | (i << 21)
 │         Attr0 (Device-nGnRnE), AP=0b00 (EL1 RW), PXN=1, UXN=1, AF=1
 │         Covers GICv2 (0x0800_0000), PL011 UART0 (0x0900_0000), VirtIO-MMIO (0x0A00_0000)
 │
 ├── L1[1] -> mmu_l2_ram | 0x3  (0x4000_0000 – 0x7FFF_FFFF)
 │     ├── L2[0]      (0x4000_0000 – 0x401F_FFFF): 0x0040_0000_4000_0705
 │     │              Kernel image (0x4008_0000), .bss, tables, SP_EL1 stacks
 │     │              Attr1 (Normal WBWA), SH=Inner, AP=0b00 (EL1 RW), PXN=0, UXN=1
 │     ├── L2[1]      (0x4020_0000 – 0x403F_FFFF): 0x0020_0000_4020_0745
 │     │              2 MiB EL0t User Arena (1984 KiB image + 64 KiB SP_EL0 stack)
 │     │              Attr1 (Normal WBWA), SH=Inner, AP=0b01 (EL1/EL0 RW), PXN=1, UXN=0
 │     ├── L2[2..63]  (0x4040_0000 – 0x47FF_FFFF): 0x0040_0000_4000_0705 | (i << 21)
 │     │              Remaining 124 MiB Kernel-only DRAM (AP=0b00, UXN=1)
 │     └── L2[64..511]: Invalid (0) -> Translation Fault on access
 │
 └── L1[2..511]: Invalid (0) -> Translation Fault on access
```

Hardware enforcement guarantees two critical boundaries:
1. **`EL0t` cannot touch kernel memory or MMIO:** `AP[2:1] = 0b00` on `L1[0]`, `L2[0]`, and `L2[2..63]` causes any `EL0t` load/store outside `0x4020_0000`–`0x403F_FFFF` to raise an `EL0` Permission Fault.
2. **`EL1` cannot execute user memory:** `PXN = 1` on `L2[1]` prevents privileged instruction fetch from the user arena, while `UXN = 0` allows `EL0t` execution inside the arena.

---

## 3. Symmetric 4-Core Cortex-A72 SMP & Interrupts (`src/smp.S`, `src/spinlock.S`, `src/gic.S`, `src/timer.S`, `src/sched.S`)

### Secondary Core Bring-Up (`src/boot.S`, `src/smp.S`)

1. Core `0` records itself online (`cpu_online[0] = 1` via `stlr`) and invokes PSCI `CPU_ON` (`0xC400_0003`) for cores `1`, `2`, and `3` with entry address `secondary_entry`.
2. Each secondary core enters `secondary_entry` (`src/boot.S`):
   - Masks DAIF and, if at `EL2`, sets `HCR_EL2.RW = 1` and `CNTHCTL_EL2` bits `0..1` (`EL1PCTEN`, `EL1PCEN`) so `EL1` can read `CNTPCT_EL0` and arm `CNTP_*_EL0`, then drops to `EL1h` via `eret`.
   - Enables `CPACR_EL1.FPEN`, selects `SP_EL1`, validates `1 <= (MPIDR_EL1 & 0xFF) <= 3`, and assigns a dedicated 4 KiB stack in `secondary_stacks` (`secondary_stacks + (cpu_id << 12)`).
   - Branches to `smp_secondary_main` (`src/smp.S`).
3. `smp_secondary_main` installs `VBAR_EL1` (`exceptions_init`), enables the MMU with the shared `mmu_l1` tables (`mmu_init_secondary`), enables its banked GICv2 CPU interface (`gic_init_cpu`), arms its local 100 Hz timer (`timer_init_cpu`), registers its pinned `idle-<cpu>` task (`sched_register_idle`), publishes `cpu_online[cpu] = 1` with `stlr; dsb ish; sev`, unmasks IRQs, and enters a `wfi` idle loop.
4. Core `0` polls `cpu_online[cpu]` with `ldar` for up to 1 second (`CNTFRQ_EL0` ticks) per core.

### Pre-MMU-Safe Exclusive Spinlocks (`src/spinlock.S`)

ARMv8 exclusive monitors (`ldaxr`/`stxr`) require cacheable Normal memory (MMU enabled) to behave reliably. `spin_lock` and `spin_unlock` check `SCTLR_EL1.M` (`tbz x1, #0`) first:
- **MMU off (early single-core boot):** Return immediately as a no-op so early UART output works before `mmu_init`.
- **MMU on (SMP):** `spin_lock` uses `sevl` / `wfe` + `ldaxr`/`stxr` acquire-exclusive loop; `spin_unlock` clears the 32-bit lock word with `stlr wzr, [x0]` (which automatically signals waiting cores out of `wfe`).

Three kernel locks serialize shared state: `uart_lock` (`src/uart.S`), `sched_lock` (`src/sched.S`), and `blk_lock` (`src/virtio_blk.S`).

### GICv2 Interrupt Controller & 100 Hz Generic Timer (`src/gic.S`, `src/timer.S`)

- **Distributor (`GICD` at `0x0800_0000`):** Core `0` enables the distributor globally (`GICD_CTLR = 1`). Private Peripheral Interrupts (INTIDs `0..31`, including `SGI 0` and `PPI 30`) have banked enable (`GICD_ISENABLER0`) and priority (`GICD_IPRIORITYR`) registers per CPU.
- **CPU Interface (`GICC` at `0x0801_0000`):** Each core sets `GICC_PMR = 0xFF` (accept all priorities) and `GICC_CTLR = 1`.
- **Per-Core Generic Timer (`PPI 30`):** `timer_init` computes `timer_reload = CNTFRQ_EL0 / 100` (falling back to `62,500,000` if zero). Each core writes `CNTP_TVAL_EL0 = timer_reload`, enables `CNTP_CTL_EL0 = 1`, and enables `INTID 30` in its banked GICv2 distributor.
- **IRQ Dispatch (`irq_dispatch` in `src/exceptions.S`):**
  1. Reads raw `GICC_IAR` (`gic_ack_irq`) and extracts `INTID = IAR & 0x3FF`; spurious IDs (`>= 1020`) return immediately.
  2. `INTID == 30` (timer): `timer_irq_handler` increments `core_ticks[cpu]` and reloads `CNTP_TVAL_EL0`.
  3. `INTID == 0` (reschedule IPI): `smp_record_sgi` increments `sgi_counts[cpu]`.
  4. **Critical ordering:** Writes the original raw `IAR` to `GICC_EOIR` *before* calling `sched_on_tick` so the active interrupt priority is dropped before any `context_switch`.

### 8-Slot Symmetric SMP Scheduler (`src/sched.S`)

The scheduler manages an 8-slot array `tcb_table` of 64-byte Task Control Blocks (512 bytes total) and a 4-entry `current_task[0..3]` array:

| Offset | Size | Field | Description |
| --- | --- | --- | --- |
| `+0x00` | 8 B | `sp` | Saved `SP_EL1` pointing to the 96-byte `context_switch` frame |
| `+0x08` | 8 B | `TCB_STATE` | `0` = `UNUSED`, `1` = `READY`, `2` = `RUNNING`, `3` = `SLEEPING` |
| `+0x10` | 8 B | `TCB_ID` | Slot index (`0`–`7`) |
| `+0x18` | 8 B | `TCB_SWITCHES` | Number of times scheduled onto a CPU |
| `+0x20` | 8 B | `TCB_TICKS` | Timer / SGI ticks charged to this task |
| `+0x28` | 8 B | `TCB_NAME` | Pointer to NUL-terminated task name |
| `+0x30` | 4 B | `TCB_AFFINITY` | Signed 32-bit affinity: `0..3` pinned, `-1` = `ANY` online CPU |
| `+0x34` | 4 B | `TCB_LAST_CPU` | Last CPU ID that ran this task |
| `+0x38` | 8 B | `TCB_WAKE_TICK` | Core `0` tick deadline for `SLEEPING` tasks |

Slot allocation:
- **Slot `0`:** `shell` (pinned to CPU `0`, uses the 16 KiB boot stack).
- **Slots `1`–`3`:** `idle-1`, `idle-2`, `idle-3` (pinned to CPUs `1`–`3`, using `secondary_stacks`).
- **Slots `4`–`7`:** Dynamically spawned `ANY`-affinity (`-1`) tasks (e.g., `worker-a`, `worker-b`), each with a 4 KiB stack in `task_stacks`.

Key concurrency invariants:
- **Locked stack handoff:** Every state transition executes with local IRQs masked (`DAIF.I = 1`) and `sched_lock` held. `context_switch` pushes `x19`–`x30` (96 bytes), stores the outgoing `sp` into the outgoing TCB, switches `sp` to the incoming task's saved `sp`, pops `x19`–`x30`, and returns to `.Lunlock` (or `task_trampoline` on first dispatch) where `sched_lock` is released on the *incoming* stack. This guarantees no other core can claim the outgoing task until its register frame is completely written.
- **Immediate SMP wakeup (`SGI 0`):** `sched_spawn` releases `sched_lock` and calls `gic_send_sgi(0, 0x0e)` (writing `GICD_SGIR` at `0x0800_0F00` with `CPUTargetList = 0b00001110`) to wake Cores `1`–`3` immediately.
- **Wrap-around-safe `sched_sleep`:** Clamps durations above `MAX_SLEEP_TICKS` (`0x7FFF_FFFF_FFFF_FFFF`) to prevent signed 64-bit wrap-around, records `wake_tick = core0_ticks + clamped_duration`, marks `TCB_STATE = SLEEPING`, and reschedules. On every Core `0` tick, `sched_on_tick` wakes sleepers whose signed difference `(now - wake_tick) >= 0` back to `READY`.

---

## 4. Storage, `TalosFS`, and Userspace Loader (`src/virtio_blk.S`, `src/ramfs.S`, `src/elf.S`, `src/syscall.S`)

### VirtIO-Blk MMIO Driver (`src/virtio_blk.S`)

- **Bus probe (`blk_init`):** Scans all 32 QEMU VirtIO-MMIO slots (`0x0a00_0000`–`0x0a00_3e00`, `0x200` stride) for Magic `0x74726976` (`"virt"`), `DeviceID == 2` (block device), and `Version == 1` (Legacy) or `2` (Modern). If none is found, `blk_present` stays `0` and the kernel boots cleanly without storage.
- **Feature negotiation & transport setup:**
  - Resets the device (`DEVICE_STATUS = 0`), sets `ACKNOWLEDGE | DRIVER`, reads `VIRTIO_BLK_F_RO` (feature bit `5`) to detect read-only media, and clears all driver features except `VIRTIO_F_VERSION_1` (bit `32`) on Modern v2 devices.
  - **Modern v2:** Verifies `FEATURES_OK`, writes 64-bit physical addresses for `QUEUE_DESC`, `QUEUE_DRIVER`, and `QUEUE_DEVICE`, and sets `QUEUE_READY = 1`.
  - **Legacy v1:** Writes `GUEST_PAGE_SIZE = 4096`, `QUEUE_ALIGN = 4096`, and `QUEUE_PFN = vq_mem >> 12`.
  - Sets `DRIVER_OK` and reads the 64-bit sector capacity at MMIO offset `0x100`–`0x104` (guarding against config changes via `CONFIG_GEN` at `0x0fc` on v2).
- **Split Virtqueue DMA (`vq_mem`, 8 KiB, 4 KiB-aligned, `QUEUE_SIZE = 8`):**
  - `+0x000`: Descriptor table (8 × 16 bytes = 128 bytes).
  - `+0x080`: Available ring (`flags = VRING_AVAIL_F_NO_INTERRUPT`, `idx`, `ring[8]`).
  - `+0x1000`: Used ring (`flags`, `idx`, `ring[8]`).
- **3-Descriptor Request Chain (`blk_read_sector` / `blk_write_sector`):** Serialized by `blk_lock`:
  1. `desc[0]`: 16-byte `blk_req_hdr` (`type = 0` IN / `1` OUT, `reserved = 0`, `sector`), `NEXT = 1`, `next = 1`.
  2. `desc[1]`: 512-byte caller buffer, `NEXT = 1`, `next = 2` (plus `WRITE = 2` for reads).
  3. `desc[2]`: 1-byte `blk_status` initialized to `0xFF`, `WRITE = 2`.
- **DMA memory ordering:** Publishes the ring slot followed by `dmb ishst`, increments `avail.idx`, executes `dsb sy` before writing `QUEUE_NOTIFY = 0`, polls `used.idx` with `ldarh` (up to `10,000,000` iterations; on timeout resets the device to halt DMA and takes it offline), issues `dmb ishld`, acknowledges `INTERRUPT_STATUS`, and checks `blk_status == 0`.

### `TalosFS` Read-Only RAMFS (`src/ramfs.S`)

`TalosFS` is embedded in `.rodata` as `ramfs_table`: an array of 32-byte entries (`name_ptr`, `data_ptr`, `size`, `flags` where `0 = FILE`, `1 = EXEC`) terminated by an all-zero 32-byte sentinel.
- Text files: `motd.txt`, `about.txt`.
- Inline flat `.bin` executables: `hello.bin`, `reader.bin`, `fault.bin`, `blktest.bin`.
- Standalone ELF64 executables included via `.incbin`: `echo.elf`, `sysinfo.elf`, `selftest.elf`.

### Userspace Image Loader, Cache Maintenance & `EL0t` Entry (`src/elf.S`, `src/syscall.S`)

1. **Full Arena Wipe (`.Lzero_user_arena`):** Before loading *any* executable (ELF64 or flat `.bin`), the kernel zeroes the entire 2 MiB `EL0t` window (`0x4020_0000`–`0x403F_FFFF`, including code gaps, `.bss`, and the 64 KiB `SP_EL0` stack) in 64-byte loops, cleans D-cache lines (`dc cvau` stepped by `4 << CTR_EL0.DminLine`), executes `dsb ish`, invalidates all inner-shareable instruction caches (`ic ialluis`), and finishes with `dsb ish; isb`.
2. **ELF64 Validation & Loading (`elf64_load` in `src/elf.S`):**
   - Inspects the `\x7fELF` magic in `user_exec_image` and validates `ELFCLASS64`, `ELFDATA2LSB`, `ET_EXEC`, `EM_AARCH64` (`183`), `e_ehsize == 64`, `e_phentsize >= 56`, `1 <= e_phnum <= 16`, and table bounds before writing a single byte to user RAM.
   - Verifies every `PT_LOAD` segment has `p_filesz <= p_memsz`, fits inside the file, maps strictly inside `[0x4020_0000, 0x403F_0000)` (preserving the top 64 KiB for `SP_EL0`), does not overlap any other non-empty `PT_LOAD` segment, and that 4-byte-aligned `e_entry` falls inside an executable (`PF_X`) `PT_LOAD` segment.
   - Copies `p_filesz`, zeroes `[p_vaddr + p_filesz, p_vaddr + p_memsz)`, and synchronizes caches per segment (`dc cvau` by `DminLine`, `dsb ish`, `ic ivau` by `IminLine`, `dsb ish`, `isb`).
3. **Flat Binary Fallback (`user_exec_blob`):** Accepts payloads `1..1 MiB`, copies to `0x4020_0000`, cleans/invalidates D/I caches (`dc cvau` / `ic ivau`), and enters at `0x4020_0000`.
4. **`EL0t` Trampoline (`user_exec` / `user_exit_to_kernel`):** Saves kernel `x19`–`x30` and `DAIF` on `SP_EL1`, records `user_return_sp`, resets all 4 per-process 24-byte `fd_table` slots (`in_use`, `entry_ptr`, `offset`), sets `SP_EL0 = 0x403F_F000`, `ELR_EL1 = entry`, `SPSR_EL1 = 0` (`EL0t`, DAIF unmasked), zeroes `x0`–`x30`, and executes `eret`. Both `SYS_EXIT` and isolated `EL0` faults unwind cleanly through `user_exit_to_kernel`.

---

## 5. Module Dependency Map

```text
                       ┌──────────────────────────┐
                       │   src/boot.S (_start,    │
                       │    secondary_entry)      │
                       └──────┬────────────┬──────┘
                              │ Core 0     │ Cores 1..3
                              ▼            ▼
                       ┌────────────┐  ┌──────────────────┐
                       │ src/main.S │  │   src/smp.S      │
                       │  (kmain)   │◄─┤(smp_secondary_   │
                       └──┬──┬──┬───┘  │ main, CPU_ON)    │
                          │  │  │      └──┬───┬───┬───┬───┘
       ┌──────────────────┘  │  └─────────┼───┘   │   │
       ▼                     ▼            ▼       ▼   ▼
┌─────────────┐       ┌────────────┐ ┌────────┐ ┌────────┐ ┌───────────┐
│ src/shell.S │──────►│src/sched.S │ │src/    │ │src/    │ │src/       │
│  (20 cmds)  │       │(8 TCBs,    │ │mmu.S   │ │gic.S   │ │timer.S    │
└──┬──┬───┬───┘       │context_sw) │ │(L1/L2) │ │(PPI30, │ │(100 Hz)   │
   │  │   │           └─────┬──────┘ └────────┘ │ SGI0)  │ └─────┬─────┘
   │  │   │                 │                   └───▲────┘       │
   │  │   ▼                 ▼                       │            ▼
   │  │ ┌──────────────┐ ┌──────────────────┐   ┌───┴───────────────┐
   │  │ │src/syscall.S │ │  src/spinlock.S  │   │ src/vectors.S +   │
   │  │ │(12 SVCs, FDs)│ │(ldaxr/stxr/stlr) │   │ src/exceptions.S  │
   │  │ └──┬────┬───┬──┘ └────▲──────▲──────┘   └───────────────────┘
   │  │    │    │   │         │      │
   │  ▼    ▼    │   ▼         │      │
   │ ┌────────┐ │ ┌──────────────┐   │
   │ │src/    │ │ │src/          │───┘
   │ │elf.S   │ │ │virtio_blk.S  │
   │ └────────┘ │ │(v1/v2 DMA)   │
   ▼            ▼ └──────────────┘
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ src/ramfs.S  │◄──┤  user/*.S    │   │ src/uart.S + │
│ (TalosFS +   │   │ (echo,       │   │ src/string.S │
│  .incbin)    │   │  sysinfo,    │   │ (PL011, fmt) │
└──────────────┘   │  selftest)   │   └──────────────┘
                   └──────────────┘
```

### File-by-File Breakdown

| File | Subsystem | Key Exported Symbols |
| --- | --- | --- |
| `linker.ld` | Kernel linker script | Maps kernel at `0x4008_0000`, defines `__bss_start`, `__bss_end`, `__stack_top` (16 KiB) |
| `src/boot.S` | Reset & EL drop | `_start`, `secondary_entry` (`secondary_stacks` 3 × 4 KiB) |
| `src/main.S` | Boot orchestrator | `kmain`, `worker_a_cpu_hits`, `worker_b_cpu_hits` |
| `src/vectors.S` | Exception table | `vectors` (2048-byte aligned, 16 slots × 128 B, 272 B trap frames) |
| `src/exceptions.S` | Trap & PSCI | `exceptions_init`, `irq_enable`, `irq_disable`, `irq_dispatch`, `el0_sync_dispatch`, `panic_exception`, `psci_system_off`, `psci_system_reset` |
| `src/mmu.S` | Stage-1 MMU | `mmu_init`, `mmu_init_secondary` (`mmu_l1`, `mmu_l2_dev`, `mmu_l2_ram`) |
| `src/gic.S` | GICv2 driver | `gic_init`, `gic_init_cpu`, `gic_enable_irq`, `gic_ack_irq`, `gic_eoi_irq`, `gic_send_sgi` |
| `src/timer.S` | Generic Timer | `timer_init`, `timer_init_cpu`, `timer_irq_handler`, `timer_get_ticks`, `timer_get_core_ticks` |
| `src/spinlock.S` | Synchronization | `spin_lock`, `spin_unlock` |
| `src/smp.S` | 4-core SMP | `smp_init`, `smp_secondary_main`, `smp_is_online`, `smp_online_count`, `smp_record_sgi`, `smp_get_sgi_count` |
| `src/sched.S` | Task scheduler | `sched_lock`, `context_switch`, `sched_init`, `sched_register_idle`, `sched_spawn`, `sched_yield`, `sched_sleep`, `sched_on_tick`, `sched_get_tcb` |
| `src/syscall.S` | EL0t & syscalls | `user_exec`, `user_exit_to_kernel`, `syscall_dispatch`, `user_exec_image`, `user_exec_blob`, `user_run_demo` |
| `src/elf.S` | ELF64 loader | `elf64_load` |
| `src/ramfs.S` | In-memory FS | `ramfs_lookup`, `ramfs_get_entry`, `ramfs_table` |
| `src/virtio_blk.S` | Block storage | `blk_init`, `blk_read_sector`, `blk_write_sector`, `blk_get_info` |
| `src/uart.S` | Serial I/O | `uart_init`, `uart_putc`, `uart_getc`, `uart_puts`, `uart_puthex`, `uart_putdec` |
| `src/string.S` | Parsing utils | `strcmp`, `skip_spaces`, `parse_hex64`, `parse_u64` |
| `src/shell.S` | Interactive CLI | `shell_readline`, `shell_run` (20 commands) |
| `user/user.ld` | User linker script | Links standalone `EL0t` ELF64 programs at `0x4020_0000` |
| `user/echo.S` | User binary | `echo.elf` — interactive `SYS_GETC` / `SYS_WRITE` line echo |
| `user/sysinfo.S` | User binary | `sysinfo.elf` — `.bss` zeroing, `SYS_CPU_ID`, and `SYS_GETTICKS` check |
| `user/selftest.S` | Regression suite | `selftest.elf` — 18 adversarial `EL0t` ABI, bounds, arena-zeroing, FD, VirtIO-Blk, and sleep checks |
