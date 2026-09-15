# Ubuntu 24.04 Chroot on Rooted Android

[Português do Brasil](README.pt-BR.md)

## Overview

This document describes the procedure used in this project to install Ubuntu 24.04 as a chroot environment on rooted Android devices.

The ARM64 procedure was tested on:

- Samsung Galaxy A15
- Motorola One (`deen`)

Both devices use the same directory layout and startup conventions:

```text
/data/local/ubuntu24
```

The Ubuntu environment runs as a **chroot**, not as a virtual machine.

Therefore, Ubuntu uses the Android device's Linux kernel and has access to kernel resources exposed to the chroot, including the device network interfaces.

The LG K11 Plus used in this project is different because its installed Android userspace is 32-bit ARM. Its ARMHF setup is documented separately where architecture-specific differences are relevant.

---

## Environment used in this project

The ARM64 installations documented here use:

```text
Ubuntu Base:   24.04.4 LTS
Architecture:  ARM64 / aarch64
Rootfs file:   ubuntu-base-24.04.4-base-arm64.tar.gz
Chroot path:   /data/local/ubuntu24
```

The rootfs SHA-256 verified during the installations was:

```text
04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2
```

Always verify the checksum of the image you actually download against the checksum published for that release by Ubuntu.

---

## Architecture

The environment can be represented as:

```text
Android device
      |
      +-- Linux kernel
             |
             +-- Android userspace
             |
             +-- Ubuntu 24.04 chroot
                     |
                     +-- GNU/Linux userspace
                     |
                     +-- PostgreSQL
```

The Ubuntu chroot does not boot another Linux kernel.

This distinction becomes particularly important when dealing with shared memory, networking, process permissions and other kernel-dependent functionality.

---

## Requirements

Before starting, the Android device must have root access.

The procedure also assumes:

- ADB access from a Linux computer
- sufficient free storage under `/data`
- an architecture compatible with the selected Ubuntu rootfs
- a working Android network connection
- a shell with root privileges on Android

Verify that the device is visible:

```bash
adb devices -l
```

Do not publish real device serial numbers unnecessarily.

Throughout this documentation:

```text
<DEVICE_SERIAL>
```

means the serial reported by `adb devices`.

---

## 1. Verify the Android architecture

Before downloading a rootfs, verify the device architecture.

From the Android shell:

```bash
adb -s <DEVICE_SERIAL> shell
```

Then:

```bash
uname -m
getprop ro.product.cpu.abi
getprop ro.product.cpu.abilist
```

For the ARM64 devices used in this project, the environment is compatible with an ARM64 Ubuntu Base rootfs.

Do not assume that an ARMv8-capable CPU means that the installed Android userspace is 64-bit.

The LG K11 Plus used in this project is an example of a device with an ARMv8-capable processor but a 32-bit Android environment.

---

## 2. Download Ubuntu Base

The ARM64 rootfs used during these experiments was:

```text
ubuntu-base-24.04.4-base-arm64.tar.gz
```

It was obtained from the official Ubuntu Base releases.

On the Linux computer, for the exact version used in these experiments:

```bash
cd ~/Downloads

wget https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.4/release/ubuntu-base-24.04.4-base-arm64.tar.gz
```

Verify the downloaded file:

```bash
ls -lh ubuntu-base-24.04.4-base-arm64.tar.gz

sha256sum ubuntu-base-24.04.4-base-arm64.tar.gz
```

For the rootfs used in this project, the result was:

```text
04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2
```

---

## 3. Transfer the rootfs with ADB

Transfer the archive to a temporary location on Android:

```bash
adb -s <DEVICE_SERIAL> push \
  ~/Downloads/ubuntu-base-24.04.4-base-arm64.tar.gz \
  /data/local/tmp/
```

Enter the Android shell:

```bash
adb -s <DEVICE_SERIAL> shell
```

Become root:

```bash
su
```

Verify the transferred file again:

```bash
ls -lh /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz

sha256sum /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz
```

The second checksum verification is intentional.

It verifies that the archive present on the Android device is identical to the archive verified on the computer.

---

## 4. Check available storage

Before extracting the rootfs:

```bash
df -h /data
```

Also inspect the existing layout:

```bash
ls -lah /data/local
```

This is especially important when another Linux chroot already exists on the device.

During the Galaxy A15 migration used in this project, the layout temporarily contained:

```text
/data/local/ubuntu    old Ubuntu 22.04 environment
/data/local/ubuntu24  new Ubuntu 24.04 environment
```

The new environment was intentionally installed separately so that the old environment was not overwritten.

---

## 5. Create the Ubuntu 24.04 directory

As Android root:

```bash
mkdir -p /data/local/ubuntu24
```

Then:

```bash
cd /data/local/ubuntu24
```

---

## 6. Extract Ubuntu Base

Extract the rootfs:

```bash
tar -xzf /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz
```

Inspect the resulting directory:

```bash
ls -la /data/local/ubuntu24 | head -30
```

The installation used in this project produced the standard merged `/usr` layout:

```text
bin  -> usr/bin
lib  -> usr/lib
sbin -> usr/sbin
```

Verify it:

```bash
ls -l /data/local/ubuntu24/bin
ls -l /data/local/ubuntu24/lib
ls -l /data/local/ubuntu24/sbin
```

---

## 7. Mount the required kernel filesystems

Before entering the chroot, mount the Android kernel interfaces that Ubuntu needs:

```bash
mount --bind /dev /data/local/ubuntu24/dev
mount --bind /dev/pts /data/local/ubuntu24/dev/pts
mount -t proc proc /data/local/ubuntu24/proc
mount -t sysfs sysfs /data/local/ubuntu24/sys
```

The tested setup did not require a separate `/run` mount.

These mounts are important because the chroot shares the Android Linux kernel.

---

## 8. Configure DNS

The tested environment used:

```bash
rm -f /data/local/ubuntu24/etc/resolv.conf
```

Then:

```bash
echo 'nameserver 1.1.1.1' > /data/local/ubuntu24/etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /data/local/ubuntu24/etc/resolv.conf
```

Verify:

```bash
cat /data/local/ubuntu24/etc/resolv.conf
```

Expected configuration:

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
```

---

## 9. Configure `/etc/hosts`

Create a minimal hosts file:

```bash
cat > /data/local/ubuntu24/etc/hosts <<'EOF'
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
EOF
```

This avoids hostname resolution problems for `localhost` inside the chroot.

---

## 10. Enter Ubuntu

Enter the new environment:

```bash
chroot /data/local/ubuntu24 /bin/bash
```

On the minimal Ubuntu Base installation, a message such as:

```text
bash: groups: command not found
```

may initially appear.

This was observed during the tested installation and did not prevent the chroot from operating.

---

## 11. Prepare the shell environment

Inside Ubuntu:

```bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

export TMPDIR=/tmp
export TMP=/tmp
export TEMP=/tmp
```

The temporary directory variables are particularly useful in this Android/chroot environment because some package installation and build operations otherwise may try to use unsuitable temporary locations inherited from Android.

---

## 12. Verify Ubuntu

Check the distribution:

```bash
cat /etc/os-release
```

Check the architecture:

```bash
uname -m
```

For the ARM64 installations:

```text
aarch64
```

Check the environment:

```bash
echo "$PATH"
echo "$TMPDIR"
```

---

## 13. Test DNS

For example:

```bash
getent hosts ports.ubuntu.com
```

Successful resolution confirms that DNS is working from inside the chroot.

---

## 14. Configure APT for the Android chroot

A special APT configuration was used successfully in the tested Android chroot environments:

```bash
cat > /etc/apt/apt.conf.d/99android-chroot <<'EOF'
APT::Sandbox::User "root";
Acquire::ForceIPv4 "true";
EOF
```

Verify:

```bash
cat /etc/apt/apt.conf.d/99android-chroot
```

Then:

```bash
apt update
```

During one documented Galaxy A15 installation, `apt update` completed successfully and downloaded approximately 35.8 MB of package metadata.

The important result is that package repository access worked correctly inside the chroot.

---

## 15. Upgrade the base environment

After a successful `apt update`, the tested procedure used:

```bash
DEBIAN_FRONTEND=noninteractive apt upgrade -y
```

Then:

```bash
dpkg --configure -a
```

The noninteractive frontend is useful for this minimal chroot environment.

---

## 16. Install networking tools

Ubuntu Base is intentionally minimal.

For example, the `ip` command was initially unavailable.

Install it with:

```bash
apt install -y iproute2
```

Then the chroot can inspect the Android device's network interfaces:

```bash
ip link show wlan0
ip -4 addr show wlan0
ip route
```

This demonstrates an important property of the architecture: the Ubuntu chroot sees the networking provided by the Android device rather than using a virtual network adapter belonging to a VM.

---

## 17. Build tools

Before compiling the software used later in this project, verify the required tools.

The tested environments eventually provided:

```bash
which gcc
which make
which wget
which curl
which git
```

Example expected paths:

```text
/usr/bin/gcc
/usr/bin/make
/usr/bin/wget
/usr/bin/curl
/usr/bin/git
```

Install missing development tools as required before proceeding to the `android-shmem` and PostgreSQL build stages.

---

## 18. Startup and shutdown scripts

This repository contains the scripts actually used by the tested devices:

```text
scripts/android/start-ubuntu.sh
scripts/android/stop-ubuntu.sh
```

The startup script mounts the required filesystems and enters the chroot.

The current project version also integrates PostgreSQL startup.

The shutdown script stops PostgreSQL before unmounting the Ubuntu environment.

This is important: do not unmount the chroot filesystems while PostgreSQL is still running.

See:

```text
../scripts/README.md
```

for the script documentation.

---

## 19. Shared network namespace

Because this is a chroot and not a VM, the network architecture can be thought of as:

```text
                     Android device
                           |
                        wlan0
                           |
                    Linux kernel
                     /          \
                    /            \
           Android userspace   Ubuntu chroot
                                   |
                               PostgreSQL
```

If Android has, for example:

```text
192.168.1.50
```

the PostgreSQL server running inside the Ubuntu chroot can listen through that device network interface when PostgreSQL and the Android environment are configured appropriately.

There is no separate VM IP address merely because Ubuntu is running in a chroot.

---

## 20. Reboot considerations

The bind mounts and pseudo-filesystems used by the chroot are not permanent Android mounts.

After a device reboot they must be mounted again before the Ubuntu environment is used.

This is one reason the project uses:

```text
/data/local/start-ubuntu.sh
```

to prepare the environment consistently.

---

## 21. ARM64 versus ARMHF

Do not select the Ubuntu rootfs solely from the CPU marketing specification.

Check the actual execution environment.

The Galaxy A15 and Motorola One installations documented here use ARM64/aarch64.

The LG K11 Plus experiment uses a 32-bit ARM environment and therefore required an ARMHF Ubuntu environment and additional compatibility work later in the project.

This distinction becomes especially important when compiling PostgreSQL and `android-shmem`.

---

## 22. What comes next

Once Ubuntu is operating correctly, the project continues with:

```text
Ubuntu 24.04 chroot
        |
        v
development tools
        |
        v
android-shmem
        |
        v
PostgreSQL compatibility patch
        |
        v
shared-memory validation
        |
        v
PostgreSQL 18.6 compilation
        |
        v
initdb
        |
        v
PostgreSQL startup scripts
        |
        v
network access and replication
```

The shared-memory compatibility work is documented in:

```text
../android-shmem/
```

The operational scripts are documented in:

```text
../scripts/
```

---

## Security notes

Root access gives the chroot significant access to the Android device.

Commands in this documentation should therefore be understood before being executed.

In particular:

- verify paths before using `rm`
- verify mount targets before mounting or unmounting
- do not overwrite an existing chroot unintentionally
- do not publish real device serial numbers
- do not publish credentials
- do not publish private keys
- do not publish production PostgreSQL configuration containing passwords

---

## Experimental status

This project documents an experimental environment.

The procedure worked on the devices tested by this project, but Android kernels, SELinux configurations, root solutions, storage layouts and vendor modifications vary significantly between devices.

A successful chroot does not by itself guarantee that PostgreSQL will run.

The shared-memory compatibility work documented elsewhere in this repository was required for the PostgreSQL environments tested by this project.

---

## Tested project layout

The standardized layout used by the ARM64 devices is:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

Using the same paths across devices simplified testing, replication configuration and maintenance.

---

## Project status

Ubuntu 24.04 chroot installation: **tested and functional**

ARM64 devices tested:

```text
Samsung Galaxy A15
Motorola One (deen)
```

Additional ARMHF/32-bit experimentation:

```text
LG K11 Plus
```
