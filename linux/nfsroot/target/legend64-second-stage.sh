#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Runs INSIDE the riscv64 Debian tree as PID 1 (kernel option
# init=/legend64-second-stage.sh), either under QEMU (second-stage-qemu.sh) or on
# the board itself.  Finishes debootstrap, then applies the legend64 settings.
# Kernel command line extras understood:  legend.epoch=<unix time>  (sets the
# clock first; there is no RTC, and dpkg/apt dislike 1970).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive LC_ALL=C LANG=C
HOSTNAME_=legend64
NFS_SERVER=192.168.1.176
GATEWAY=192.168.1.1

fail() { echo; echo "LEGEND64-SECOND-STAGE: FAILED: $*"; echo "dropping to a shell"; exec /bin/sh; }

[ -e /proc/cmdline ] || mount -t proc proc /proc
[ -d /sys/kernel ] || mount -t sysfs sysfs /sys
mount -o remount,rw / 2>/dev/null
epoch=$(sed -n 's/.*legend\.epoch=\([0-9]*\).*/\1/p' /proc/cmdline)
[ -n "$epoch" ] && date -s "@$epoch" >/dev/null && echo "clock set to $(date -u)"

# Only for the unprivileged rehearsal (QEMU 9p "mapped-xattr" on a tree that was
# unpacked under fakeroot): make root own the tree.  A real, root-made tree
# already has / owned by uid 0 and skips this.
if [ "$(stat -c %u /)" != 0 ]; then
    echo "tree is not root-owned (rehearsal): chown -R root:root"
    chown -Rh 0:0 /bin /boot /debootstrap /etc /home /lib /root /run /sbin /tmp /usr /var / 2>/dev/null
    chmod 1777 /tmp /var/tmp
fi

if [ -x /debootstrap/debootstrap ]; then
    echo "LEGEND64-SECOND-STAGE: running debootstrap --second-stage (takes a while)"
    /debootstrap/debootstrap --second-stage || { tail -n 40 /debootstrap/debootstrap.log; fail "debootstrap --second-stage"; }
else
    echo "LEGEND64-SECOND-STAGE: /debootstrap is gone - second stage already done, only (re)configuring"
fi
[ -e /proc/cmdline ] || mount -t proc proc /proc

echo "LEGEND64-SECOND-STAGE: configuring"
echo "$HOSTNAME_" > /etc/hostname
cat > /etc/hosts <<EOT
127.0.0.1	localhost
127.0.1.1	$HOSTNAME_
192.168.1.51	$HOSTNAME_-eth
$NFS_SERVER	nfsserver
::1		localhost ip6-localhost ip6-loopback
EOT

# The root file system is mounted by the kernel (root=/dev/nfs or 9p under
# QEMU) before init starts, so it deliberately has no fstab line: nothing may
# remount or fsck it.
cat > /etc/fstab <<EOT
# <file system> <mount point> <type> <options> <dump> <pass>
# / is NFS, mounted by the kernel (nfsroot=...), intentionally not listed.
tmpfs	/tmp	tmpfs	nosuid,nodev,size=128m	0	0
EOT

# Network: eth0 is configured by the kernel (ip=...) and carries the root file
# system.  Nothing in user space may touch it: only "lo" is listed for ifupdown,
# systemd-networkd stays disabled, no DHCP client is installed.
mkdir -p /etc/network/interfaces.d
cat > /etc/network/interfaces <<EOT
# eth0 is set up by the kernel command line (ip=...) because / is on NFS.
# Do NOT add eth0 here (ifdown/ifup on it would cut off the root file system).
auto lo
iface lo inet loopback
source /etc/network/interfaces.d/*
EOT
systemctl disable systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service >/dev/null 2>&1
rm -f /etc/resolv.conf
echo "nameserver $GATEWAY" > /etc/resolv.conf

# Root logs in on the serial console without a password (bring-up system!).
passwd -d root >/dev/null || fail "passwd -d root"
systemctl enable serial-getty@ttyS0.service >/dev/null 2>&1

# A 25 MHz CPU is 100x slower than what the default timeouts assume.
mkdir -p /etc/systemd/system.conf.d /etc/systemd/journald.conf.d
cat > /etc/systemd/system.conf.d/10-legend64.conf <<EOT
[Manager]
DefaultTimeoutStartSec=30min
DefaultTimeoutStopSec=10min
DefaultDeviceTimeoutSec=30min
RuntimeWatchdogSec=off
EOT
cat > /etc/systemd/journald.conf.d/10-legend64.conf <<EOT
[Journal]
# keep the journal in RAM: no sync-heavy writes over NFS
Storage=volatile
RuntimeMaxUse=16M
EOT
systemctl mask apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer fstrim.timer >/dev/null 2>&1

cat > /etc/apt/sources.list <<EOT
deb http://deb.debian.org/debian trixie main
deb http://deb.debian.org/debian trixie-updates main
deb http://security.debian.org/debian-security trixie-security main
EOT
apt-get clean

echo "LEGEND64-SECOND-STAGE: installed $(dpkg-query -W -f='${Status}\n' | grep -c '^install ok installed') packages, $(dpkg --audit | wc -l) audit problems"
sync
echo "LEGEND64-SECOND-STAGE: COMPLETE"
# PID 1 must not exit.  Under QEMU this powers the VM off; on the board (no
# power-off device) it just halts - reset the board afterwards.
sync; sleep 1
poweroff -f
sleep 5
echo "(halt: you can reset the machine now)"
while :; do sleep 3600; done
