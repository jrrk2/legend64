# legend64 Linux software stack

Software for the legend64 RV64GC soft processor on the Xilinx VC707: OpenSBI,
a mainline Linux kernel, device trees, a busybox initramfs, and the scripts to
make a Debian riscv64 NFS root. Everything was built without root and proven on
QEMU; nothing here has run on the real hardware yet (see "Verified / not
verified" at the end).

## What is here

| Path | What |
|---|---|
| `out/Image` | Linux 6.18.64 kernel (unmodified mainline source, own config) |
| `out/legend64-vc707.dtb` | board device tree, NFS-root command line |
| `out/legend64-vc707-initramfs.dtb` | same board, boots the initramfs instead |
| `out/initramfs.cpio.gz` | Debian `busybox-static` (riscv64, unmodified) + `/init` |
| `out/bootmon-shim.bin` | 16-byte stand-in for the boot monitor, QEMU rehearsal only |
| `dts/legend64-vc707.dts` | device tree source (copies of both `.dtb` are kept next to it) |
| `kernel/legend64_defconfig` | kernel configuration (generated from `kernel/legend64.fragment`) |
| `kernel/patches/` | optional driver patch picked up by the build (empty: no source patch is needed) |
| `build-kernel.sh`, `build-initramfs.sh`, `build-dtb.sh` | rebuild scripts |
| `run-qemu.sh`, `scripts/qemu-drive.py` | QEMU launcher and a small non-interactive console driver |
| `nfsroot/` | scripts **for root** that create and export the Debian NFS root |
| `logs/` | build and boot logs quoted below |
| `tools/` | cross compiler etc. unpacked from Ubuntu packages (`tools/debs`), `dl/` downloads |

OpenSBI is not rebuilt: the stock Ubuntu `opensbi` 1.8.1 binary
`/home/jonathan/riscv/tools/qemu/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin`
is used as is.

## Hardware contract assumed

One hart, RV64IMAFDC, M/S/U, Sv39, no PMP, no Sstc, no `time` CSR, no ASIDs,
software-managed A/D bits, misaligned accesses trap.

| Device | Address | Size | Interrupt | Device tree |
|---|---|---|---|---|
| CLINT | `0x0200_0000` | `0x10000` | M-soft 3, M-timer 7 | `sifive,clint0`, `riscv,clint0` |
| PLIC | `0x0c00_0000` | `0x400_0000` | M-ext 11, S-ext 9 | `sifive,plic-1.0.0`, `riscv,plic0`, `riscv,ndev = 31` |
| UART | `0x1000_0000` | `0x100` | PLIC 10 | `ns16550a`, reg-shift 0, reg-io-width 1, 1843200 Hz, 115200 |
| Ethernet | `0x3000_0000` | `0x1000` | PLIC 2 | `legend,eth` (**placeholder, driver pending**) |
| RAM | `0x8000_0000` | 1 GiB | | |

`timebase-frequency` is 25 MHz. It is one value: `TIMEBASE_HZ=50000000 ./build-dtb.sh`
(or the `#define TIMEBASE_HZ` at the top of the `.dts`).

Network: board 192.168.1.51, NFS server (this host) 192.168.1.176, netmask
255.255.255.0, gateway 192.168.1.1, MAC 02:00:00:fa:b1:e5.

## Boot flow and what the boot monitor must load

| File | Size (bytes) | Load address |
|---|---|---|
| `/home/jonathan/riscv/tools/qemu/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin` | 275888 | `0x8000_0000` |
| `/home/jonathan/riscv/linux/out/Image` | 6718464 | `0x8020_0000` |
| `/home/jonathan/riscv/linux/out/legend64-vc707.dtb` (NFS root) **or** `out/legend64-vc707-initramfs.dtb` | 2090 / 2050 | `0x8600_0000` |
| `/home/jonathan/riscv/linux/out/initramfs.cpio.gz` (only with the initramfs DTB) | 1036696 | `0x8800_0000` |

Then jump to `0x8000_0000` in M-mode with `a0 = 0`, `a1 = 0x8600_0000`.
Sizes change on every rebuild; `ls -l out/` after building.

Why these addresses are safe:

* OpenSBI keeps `0x8000_0000..0x8005_ffff` (reserved in the tree it hands to Linux).
* `fw_jump.bin` jumps to `0x8020_0000` and **copies the DTB to `0x8220_0000`**
  before starting the kernel (both constants are compiled into the stock
  binary; the banner shows "Next Address 0x80200000 / Next Arg1 0x82200000").
  So the DTB the kernel uses lives at `0x8220_0000`, wherever the monitor put it.
* The kernel occupies `0x8020_0000..0x808a_3000` when running (7.0 MB, printed by
  `build-kernel.sh`), far below `0x8220_0000`. A kernel must stay under 32 MB of
  footprint for this OpenSBI binary; this one has 25 MB of headroom.
* `0x8600_0000` for the monitor's DTB copy and `0x8800_0000` for the initramfs
  collide with nothing above. The initramfs DTB records the initramfs address
  and its **exact** length (`linux,initrd-start/end`), so rerun `build-dtb.sh`
  whenever the initramfs changes, and load both files from the same build.

Command lines (in `/chosen/bootargs`):

* NFS root: `console=ttyS0,115200 earlycon root=/dev/nfs nfsroot=192.168.1.176:/srv/nfs/fable64,vers=3,tcp rw ip=192.168.1.51::192.168.1.1:255.255.255.0:legend64:eth0:off`
* initramfs: `console=ttyS0,115200 earlycon rdinit=/init`
* any other: `BOOTARGS_NFS='...' ./build-dtb.sh` or `BOOTARGS_INITRAMFS='...' ./build-dtb.sh`.
  If the UART itself is suspect, `earlycon=sbi` prints through OpenSBI instead.

## Rebuilding

Nothing needs root. Builds use at most 12 jobs (`JOBS=` to lower it).

```
./build-kernel.sh        # -> out/Image, out/kernel.config, out/System.map   (about 2 minutes)
./build-initramfs.sh     # -> out/initramfs.cpio.gz
./build-dtb.sh           # -> out/*.dtb (after build-initramfs.sh: it records the initramfs size)
./run-qemu.sh            # initramfs on QEMU, interactive, Ctrl-A X to quit
./run-qemu.sh board      # the board boot flow on QEMU (board DTB, board load addresses)
```

### Kernel

* Source: `linux-6.18.64.tar.xz` from cdn.kernel.org, sha256
  `020d4551...ade562` checked against kernel.org's `sha256sums.asc`. **No source
  patch.** `diff -r` of the build tree against a fresh unpack is empty.
* Compiler: Ubuntu `gcc-riscv64-linux-gnu` 15.2.0 / binutils 2.46, unpacked with
  `dpkg -x` under `tools/root` (the debs are in `tools/debs`).
* Config: `kernel/legend64_defconfig`. It is generated from the commented
  `kernel/legend64.fragment` by `./build-kernel.sh regen-defconfig`
  (`allnoconfig` + fragment, then `savedefconfig`); edit the fragment, not the
  defconfig. `./build-kernel.sh menuconfig` is there for experiments.
* What is in it: RV64GC with FPU, single hart (`SMP=n`, so no IPIs are ever
  sent; the SBI IPI extension is still detected), no modules (everything
  built in), SBI timer, SiFive PLIC, 8250/16550 console with OF probing and
  earlycon (plus SBI earlycon), devtmpfs with automount, tmpfs, proc, sysfs,
  initramfs (gzip only), ext4, NFS client v3/v4/4.1/4.2 with `ROOT_NFS` and
  `IP_PNP`, 9p, virtio-mmio blk/net/console/rng, and what systemd needs
  (cgroup v2 with memcg/pids/cpu/bpf, all namespaces, fhandle, autofs, inotify,
  fanotify, signalfd, timerfd, epoll, unix sockets, IPv6, seccomp filter, BPF
  syscall and JIT, PSI, tmpfs ACL/xattr, AF_ALG hash).
* What is deliberately not in it: every optional ISA extension (V, Zba, Zbb,
  Zbc, Zbkb, Zicbom, Zicboz, Zicbop, Zawrs, Zacas, Zabha, Svnapot, Svpbmt,
  vendor extensions, errata), compat (rv32) user space, EFI, PCI, USB, sound,
  DRM/fbdev, VT, input, wireless, SCSI, netfilter, swap, perf/PMU, modules.
* `STRICT_KERNEL_RWX` is off: on RISC-V it pads each kernel section to 2 MiB
  and the Image grows from 6.7 MB to 15.2 MB. Turn it on in the fragment if
  load time stops mattering.
* SBI system reset is used for reboot/poweroff, but the board has no reset
  device for OpenSBI to drive, so `reboot` and `poweroff` just halt there.

### Ethernet driver ("legend,eth") - pending

The MAC is a native descriptor-ring device that DMAs to and from system RAM.
Its register interface is not fixed yet and **no driver exists**: the device
tree has a placeholder node, nothing binds to it, and the NFS-root DTB cannot
reach its root file system until the driver is added. The build is ready for it:

* Put the driver in a patch at `kernel/patches/legend-eth.patch` (`-p1`,
  relative to the kernel source root). `build-kernel.sh` applies it when the
  file exists, appends `CONFIG_LEGEND_ETH=y` to the config, and fails loudly if
  that symbol does not survive. Without the file it builds the plain kernel.
  If the patch changes or is removed, the previously applied one is reverted
  first, so the source tree always matches the patch file.
* The easy way: `kernel/make-legend-eth-patch.sh /path/to/legend_eth.c` writes
  that patch for you. It adds `drivers/net/ethernet/legend/{legend_eth.c,Kconfig,Makefile}`
  and the only two edits to existing files (one `source` line in
  `drivers/net/ethernet/Kconfig`, one `obj-` line in
  `drivers/net/ethernet/Makefile`).
* Extra config lines the driver needs (for example `CONFIG_PHYLIB=y`) go in
  `kernel/patches/legend-eth.config`, or as `select` lines in the driver's Kconfig.
* The plumbing was tested with a stub (`kernel/patches/example/`,
  `logs/kernel-build-with-stub-patch.log`): applied, built in, reverted cleanly.
* DMA: nothing more is needed. RISC-V devices are DMA-coherent by default and
  this kernel has no non-coherent support compiled in at all
  (`ARCH_DMA_DEFAULT_COHERENT=y`, `RISCV_DMA_NONCOHERENT` off), so there is no
  `dma-coherent` property to add. The `soc` node carries an empty `dma-ranges`
  (bus address = physical address). All RAM is below 4 GiB, so no bounce
  buffering is set up. In the driver: `dma_set_mask_and_coherent(dev,
  DMA_BIT_MASK(32))`, `dma_alloc_coherent()` for the rings,
  `dma_map_single()` for packet buffers; the handles are the physical
  addresses `0x8000_0000..0xbfff_ffff`.

### Initramfs

`build-initramfs.sh` downloads `busybox-static_1.37.0-6+b9_riscv64.deb` from
Debian 13 "trixie" main (sha256 pinned from the signed Packages index), takes
the one binary out of it unmodified and adds `initramfs/init`, which mounts
devtmpfs, proc and sysfs, installs the applet links, prints a banner and runs a
shell on the console.

## QEMU

`run-qemu.sh` runs `-M virt -m 1G -smp 1` with OpenSBI `fw_jump.bin` and this CPU:

```
-cpu rv64,sv48=off,sv57=off,pmp=off,sstc=off,h=off,v=off,zba=off,zbb=off,zbc=off,zbs=off,zicbom=off,zicbop=off,zicboz=off,zicntr=off,zihpm=off,pmu-mask=0,zihintpause=off,zihintntl=off,zawrs=off,zfa=off,svadu=off,svade=on,svvptc=off,debug=off
```

That leaves `rv64imafdc_zicsr_zifencei` with Sv39, no PMP, no Sstc, no
counters CSRs (`rdtime` traps and OpenSBI emulates it, as on the board), and
page faults instead of hardware A/D updates.

Could not be turned off in QEMU 10.2.1:

* misaligned loads and stores are executed directly instead of trapping;
* ASIDs: QEMU implements 16 bits;
* `zic64b` and `ziccrse` are not settable properties (they are only statements
  about cache block size and LR/SC progress, no instructions);
* the `pause` hint and every unused CSR behave as QEMU implements them.

Differences of the machine: QEMU's CLINT ticks at 10 MHz and its PLIC has 95
sources in its own device tree; it has virtio devices, a reset device and an
RTC that the board lacks; it has no `legend,eth`.

## Debian NFS root (`nfsroot/`, needs root - not run here)

riscv64 is a release architecture of Debian 13 "trixie" (stable, 13.7 at the
time of writing), so the normal mirror `http://deb.debian.org/debian` and the
normal `debian-archive-keyring` apply; no debian-ports.

```
sudo nfsroot/make-nfsroot.sh        # 1. debootstrap --foreign (x86 host) into /srv/nfs/fable64
sudo nfsroot/second-stage-qemu.sh   # 2. second stage + configuration under QEMU (recommended)
sudo nfsroot/second-stage-qemu.sh boot   # optional: boot the result on QEMU, log in as root
sudo nfsroot/setup-nfs-server.sh    # 3. nfs-kernel-server and the export
```

* Step 2 boots QEMU (this kernel, the cut-down CPU) with the tree as its root
  file system over virtio-9p and `init=/legend64-second-stage.sh`. That script
  (`nfsroot/target/legend64-second-stage.sh`) runs `debootstrap --second-stage`
  and then configures the system. QEMU runs as root here because 9p
  `passthrough` must create root-owned files.
* The alternative is the board itself: boot the NFS-root DTB with
  `init=/legend64-second-stage.sh legend.epoch=<unix time>` appended to the
  command line (`BOOTARGS_NFS=... ./build-dtb.sh`). It is the same script, but
  expect it to take hours at 25 MHz, and it needs the Ethernet driver first.
* Configuration applied: hostname `legend64`; root logs in on the console with
  an empty password; `serial-getty@ttyS0` enabled; `/etc/fstab` without a root
  line (the kernel mounts `/`); `/etc/network/interfaces` with only `lo`,
  networkd disabled and no DHCP client, so nothing touches the kernel-configured
  `eth0`; `/etc/resolv.conf` pointing at 192.168.1.1; journal kept in RAM;
  systemd start/device timeouts raised to 30 minutes for the slow CPU; apt
  timers masked; `systemd-timesyncd` installed because there is no RTC.
* Export line written by step 3 to `/etc/exports`:
  `/srv/nfs/fable64 192.168.1.51(rw,sync,no_root_squash,no_subtree_check)`

### Rehearsal without root: what happened

`nfsroot/rehearse-unprivileged.sh` tries the whole procedure unprivileged.
Result: **stage 1 works, stage 2 FAILED in the rehearsal and is unproven.**

* Worked: `debootstrap --foreign --arch=riscv64 trixie` under fakeroot with the
  normal mirror and keyring (`logs/rehearsal-debootstrap-stage1.log`, 211 MB tree).
* Worked: carrying that tree as a tar into a QEMU 9p `mapped-xattr` export from
  the busybox initramfs (`logs/rehearsal-unpack-into-9p.log`, `UNPACK_RC=0`).
* Worked: the kernel mounting a 9p root and starting
  `/legend64-second-stage.sh` as init, which set the clock and started
  `debootstrap --second-stage`.
* **Failed:** the first `dpkg --install` (base-passwd) stopped with
  `tar: ./control: Cannot change ownership to uid 0, gid 0: Operation not permitted`
  (`logs/rehearsal-second-stage-qemu9p.log`). The same error appeared with 9p
  `security_model=none`. With `mapped-xattr` directly on a host-made tree the
  boot fails earlier (error -40: QEMU cannot follow host-created symlinks).
  The cause of the chown failure under `mapped-xattr` was **not diagnosed**
  (work was stopped). It may be an artefact of unprivileged 9p that root with
  `passthrough` does not have, but that is a guess: `second-stage-qemu.sh` as
  root has never been run.
* Never reached: the Debian configuration part of the script, a systemd boot,
  a login. So "Debian user space boots on this kernel and CPU model" is not
  shown yet; only Debian's static busybox is.
* If step 2 fails for root as well, the fallbacks are an ext4 image instead of
  9p (`mke2fs -d` of the stage-1 tree, `root=/dev/vda`, then copy the result to
  `/srv/nfs/fable64`), or the second stage on the board.
* `nfsroot/rehearsal/` (433 MB: `stage1.tar` and the half-installed
  `rootfs9p`) can be deleted.
* Kernel NFS-root path: with QEMU virtio-net and no NFS server,
  `ip=...` autoconfiguration completes and the kernel tries the NFS mount and
  gives up after 96 s as expected (`logs/qemu-nfsroot-noserver.log`). An actual
  NFS mount was not exercised (no unprivileged NFS server available here).


## Verified / not verified

Verified on QEMU 10.2.1 (`-M virt`, cut-down CPU above):

* OpenSBI 1.8.1 stock `fw_jump.bin` boots with `pmp=off`, no Sstc, no `time`
  CSR ("Boot HART PMP Count: 0", "Boot HART Base ISA: rv64imafdc").
* The kernel boots to the busybox shell and runs commands; UART interrupt,
  PLIC, SBI timer work (`logs/qemu-initramfs-boot.log`).
* `rdtime` really traps with `zicntr=off` and is emulated by OpenSBI (about
  2400 illegal-instruction traps in the first 6 s, all `rdtime`).
* The **board boot flow**: the board's initramfs DTB, the four files at the
  board load addresses, entry at `0x8000_0000` with `a0=0`, `a1=0x8600_0000`
  (`./run-qemu.sh board`, `logs/qemu-board-flow-boot.log`). OpenSBI reports
  "aclint-mtimer @ 25000000Hz", the kernel maps 31 PLIC interrupts, finds the
  initramfs through `linux,initrd-start/end` and reaches the shell.
* Sv39 with A/D faults instead of hardware updates (`svadu=off,svade=on`).
* Kernel `ip=` autoconfiguration and the NFS-root attempt (virtio-net, no server).
* The optional driver-patch path of `build-kernel.sh` (stub driver).
* Rough speed check with `-icount`: at 8 to 16 million instructions per second
  the kernel reaches `/init` 4 to 8 s after its clock starts
  (`logs/qemu-initramfs-icount-shift*.log`). This ignores cache and memory
  timing and the time before the kernel clock starts.

Not verified:

* Anything on the real hardware.
* Ethernet: no driver, no QEMU model. NFS root on the board cannot work until
  the `legend,eth` driver exists.
* A real NFS root mount, the NFS server setup, and all three root scripts
  (`make-nfsroot.sh`, `second-stage-qemu.sh` as root, `setup-nfs-server.sh`).
* Debian beyond stage 1: the second stage failed in the unprivileged rehearsal
  (above), systemd has never been booted on this kernel.
* Misaligned-access trapping (QEMU executes them). The kernel asks OpenSBI to
  delegate these traps and then emulates them itself; untested.
* ASID width 0, the 16550 as implemented in RTL (divisor ignored), 25 MHz
  behaviour of systemd timeouts.
* `reboot`/`poweroff` on the board: there is no reset device, they halt
  ("Power off not available: System halted instead" in the board-flow log).

Points for the RTL author (from what the software was seen to do):

* Linux and OpenSBI execute `rdtime` constantly (timekeeping, scheduler clock,
  user-space `clock_gettime` through the vDSO). Trap-and-emulate works but each
  read costs an M-mode trap; a read-only `time` CSR mirroring `mtime` would
  remove that. Not required.
* The kernel's `cpu_relax()` executes the `pause` hint (`0x0100000f`, a FENCE
  encoding) without checking for Zihintpause: it must be a no-op, not an
  illegal instruction.
* The idle loop executes `wfi` in S-mode with interrupts globally disabled and
  expects it to return when an enabled interrupt becomes pending.
* The device tree sets `mmu-type = "riscv,sv39"`, so this kernel does not
  probe Sv48/Sv57 by writing `satp`.
* OpenSBI emulates `rdtime` (and misaligned accesses, if they reach it) by
  reading the trapping instruction, so `mtval`/`mepc` on those traps and
  `mstatus.MPRV` need to behave per the privileged spec. This is from general
  knowledge of OpenSBI, not checked against its source here.
* A reset/poweroff register like QEMU virt's (`sifive,test1` syscon at
  `0x10_0000` with `syscon-reboot`/`syscon-poweroff` nodes) would give working
  `reboot` with no kernel change; on QEMU that arrangement is what OpenSBI uses.
* No RTC and no entropy source: the clock starts in 1970 until NTP runs, and
  the boot monitor could pass an `rng-seed` in `/chosen` if early randomness
  turns out to be slow.

