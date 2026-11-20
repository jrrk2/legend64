#!/bin/bash
# Unprivileged rehearsal of the Debian root procedure (NO root needed; this is
# what was actually run - see logs/rehearsal-*.log).  It differs from the real
# procedure only where root is unavoidable:
#   real:      root debootstrap --foreign into /srv/nfs/fable64, QEMU 9p "passthrough"
#   rehearsal: fakeroot debootstrap --foreign, tree carried into a QEMU 9p
#              "mapped-xattr" export as a tar (so the guest sees correct owners,
#              symlinks and device nodes), then the very same second-stage-qemu.sh.
# The result (nfsroot/rehearsal/rootfs9p) is only usable through QEMU 9p
# mapped-xattr; it is NOT a tree you can export over NFS.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); top=$here/..
R=$here/rehearsal; T=$top/tools/root; logs=$top/logs
drive="$top/scripts/qemu-drive.py"
mkdir -p "$R"

if [ ! -f "$R/stage1.tar" ]; then
    rm -rf "$R/rootfs" "$R/fakeroot.state"
    fakeroot -s "$R/fakeroot.state" env DEBOOTSTRAP_DIR="$T/usr/share/debootstrap" \
        "$T/usr/sbin/debootstrap" --foreign --arch=riscv64 \
        --keyring="$T/usr/share/keyrings/debian-archive-keyring.gpg" \
        --include=systemd-timesyncd,iputils-ping,netbase,ca-certificates \
        trixie "$R/rootfs" http://deb.debian.org/debian > "$logs/rehearsal-debootstrap-stage1.log" 2>&1
    fakeroot -i "$R/fakeroot.state" tar --numeric-owner -C "$R/rootfs" -cf "$R/stage1.tar" .
    rm -rf "$R/rootfs" "$R/fakeroot.state"
fi

if [ ! -d "$R/rootfs9p/etc" ]; then
    rm -rf "$R/rootfs9p"; mkdir -p "$R/rootfs9p"
    "$drive" --timeout 1800 --log "$logs/rehearsal-unpack-into-9p.log" \
        '~ # =>mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 rootfs /mnt && tar -xpf /dev/vda -C /mnt; echo UNPACK_RC=$?; sync' \
        'UNPACK_RC=0' '~ # =>ls -ln /mnt /mnt/dev | head -40; poweroff -f' 'reboot: Power down' -- \
        "$top/run-qemu.sh" initramfs \
        -fsdev local,id=rootfs,path="$R/rootfs9p",security_model=mapped-xattr \
        -device virtio-9p-device,fsdev=rootfs,mount_tag=rootfs \
        -drive file="$R/stage1.tar",format=raw,if=none,id=d0,readonly=on -device virtio-blk-device,drive=d0 > /dev/null
fi

export TARGET=$R/rootfs9p SECURITY_MODEL=mapped-xattr
if [ -e "$R/rootfs9p/debootstrap" ]; then
    "$drive" --timeout 5400 --log "$logs/rehearsal-second-stage-qemu9p.log" \
        'LEGEND64-SECOND-STAGE: (COMPLETE|FAILED)|Kernel panic' '(Power down|dropping to a shell|end Kernel panic)' -- \
        "$here/second-stage-qemu.sh" > /dev/null
    grep -a -q 'LEGEND64-SECOND-STAGE: COMPLETE' "$logs/rehearsal-second-stage-qemu9p.log"
fi

# boot the finished Debian (systemd) and log in on the serial console
"$drive" --timeout 3600 --log "$logs/rehearsal-debian-boot-qemu9p.log" \
    'legend64 login: =>root' \
    'root@legend64:~# =>uname -a; cat /etc/debian_version; dpkg --print-architecture; systemctl is-system-running; systemctl --failed --no-pager' \
    'root@legend64:~# =>systemd-analyze --no-pager; ps -e | wc -l; free -m; ip -br addr; findmnt -n /; echo DEBIAN_OK_$((6*7))' \
    'DEBIAN_OK_42' 'root@legend64:~# =>systemctl poweroff' 'reboot: Power down' -- \
    "$here/second-stage-qemu.sh" boot > /dev/null
echo "rehearsal complete"
