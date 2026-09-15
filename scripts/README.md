# Android Chroot and PostgreSQL Control Scripts

[Português (Brasil)](README.pt-BR.md)

## Overview

This directory contains the shell scripts used to control the Ubuntu 24.04 chroot environment and PostgreSQL 18.6 on the Android devices tested by this project.

The same directory structure and script names are used on all currently tested devices:

- Samsung Galaxy A15 — ARM64
- Motorola Android One (deen) — ARM64
- LG K11 Plus — ARMHF/32-bit

The scripts preserved in this repository were extracted directly from the working Samsung Galaxy A15 environment and verified before publication.

The operational layout is:

```text
Android filesystem
/data/local/
├── start-ubuntu.sh
├── stop-ubuntu.sh
└── ubuntu24/
    └── scripts/
        └── postgres/
            ├── start.sh
            ├── stop.sh
            ├── restart.sh
            └── status.sh
```

Inside the Ubuntu chroot, the PostgreSQL scripts therefore appear as:

```text
/scripts/postgres/
├── start.sh
├── stop.sh
├── restart.sh
└── status.sh
```

---

## Why Scripts Are Used Instead of systemd

The Ubuntu 24.04 environment in this project runs as a chroot hosted by Android.

It is not a virtual machine and does not boot its own Linux kernel or conventional init system.

For this reason, PostgreSQL lifecycle management is performed explicitly by scripts rather than depending on a normal `systemd` boot sequence inside the chroot.

The basic startup path is:

```text
Android
   |
   v
start-ubuntu.sh
   |
   +--> mount /dev
   +--> mount /dev/pts
   +--> mount /proc
   +--> mount /sys
   |
   v
Ubuntu 24.04 chroot
   |
   v
/scripts/postgres/status.sh
   |
   +--> PostgreSQL already running -> continue
   |
   +--> PostgreSQL stopped
             |
             v
       /scripts/postgres/start.sh
             |
             v
          setpriv
             |
             v
         postgres user
             |
             v
         LD_PRELOAD
             |
             v
    libandroid-shmem.so
             |
             v
           pg_ctl
```

---

## Android Scripts

The scripts in:

```text
scripts/android/
```

run from the Android side of the environment.

They use:

```text
#!/system/bin/sh
```

and require sufficient privileges to mount filesystems and enter the chroot.

In the tested rooted devices, they are executed with root privileges.

### `start-ubuntu.sh`

The startup script defines the Ubuntu root filesystem as:

```text
/data/local/ubuntu24
```

It prepares the following mounts:

```text
/dev
/dev/pts
/proc
/sys
```

The script first checks whether each mount already exists, avoiding unnecessary duplicate mounts.

It also prepares environment variables including:

```text
TMPDIR=/tmp
TMP=/tmp
TEMP=/tmp
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LANG=en_US.UTF-8
```

Before opening the interactive Ubuntu shell, it checks PostgreSQL using:

```text
/scripts/postgres/status.sh
```

If PostgreSQL is already running, it is left untouched.

Otherwise:

```text
/scripts/postgres/start.sh
```

is executed automatically.

Finally, the script enters the Ubuntu environment with:

```bash
exec chroot "$ROOT" /bin/bash
```

This means that entering the Ubuntu chroot also ensures that PostgreSQL is available.

---

## Safe Shutdown

`stop-ubuntu.sh` performs the reverse operation.

PostgreSQL is stopped **before** the chroot-related mounts are removed.

The shutdown path is:

```text
stop-ubuntu.sh
       |
       v
/scripts/postgres/stop.sh
       |
       v
wait for PostgreSQL
       |
       +--> failure
       |      |
       |      +--> abort unmount
       |
       +--> stopped
              |
              v
          short wait
              |
              v
        unmount /dev/pts
        unmount /dev
        unmount /proc
        unmount /sys
```

This ordering is intentional.

If `stop.sh` returns an error, `stop-ubuntu.sh` prints:

```text
ERRO: PostgreSQL nao foi parado.
Ubuntu NAO sera desmontado.
```

and terminates without unmounting the Ubuntu environment.

This protects the PostgreSQL process from having its chroot environment dismantled while it may still be running.

The script additionally polls PostgreSQL status for up to approximately ten seconds and performs a short additional wait before unmounting.

---

## PostgreSQL Scripts

The scripts under:

```text
scripts/postgres/
```

run inside the Ubuntu 24.04 chroot.

All currently preserved scripts use:

```text
PGHOME=/usr/local/pgsql18
PGDATA=$PGHOME/data
SHMEM=/usr/local/lib/libandroid-shmem.so
```

Therefore the expected installation layout is:

```text
/usr/local/pgsql18/
├── bin/
├── data/
└── logfile

/usr/local/lib/
└── libandroid-shmem.so
```

---

## Running PostgreSQL as the `postgres` User

The Android/chroot environment requires some handling that differs from a conventional Ubuntu server.

The PostgreSQL scripts use:

```bash
setpriv \
  --reuid=postgres \
  --regid=postgres \
  --groups=1000,3003
```

This switches execution from the chroot root user to the unprivileged PostgreSQL account while retaining the supplementary groups required by the tested Android environment.

The numeric supplementary groups are environment-specific and should not be copied blindly to unrelated devices.

Users reproducing this setup should verify the groups required by their own Android/chroot environment.

---

## `LD_PRELOAD`

PostgreSQL is launched with:

```bash
env LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

This causes the modified `android-shmem` compatibility library documented elsewhere in this repository to be loaded into the PostgreSQL process.

The complete startup command ultimately invokes:

```text
/usr/local/pgsql18/bin/pg_ctl
```

with the PostgreSQL data directory:

```text
/usr/local/pgsql18/data
```

The compatibility library and its patch are documented in:

```text
android-shmem/
```

---

## Starting PostgreSQL

`start.sh` runs:

```text
pg_ctl -D $PGDATA -l $PGHOME/logfile start
```

through `setpriv` and with the compatibility library loaded through `LD_PRELOAD`.

The PostgreSQL server log is written to:

```text
/usr/local/pgsql18/logfile
```

---

## Stopping PostgreSQL

`stop.sh` runs:

```text
pg_ctl -D $PGDATA stop
```

using the same user and compatibility environment.

The Android-side `stop-ubuntu.sh` depends on the exit status of this script.

If PostgreSQL cannot be stopped successfully, the Ubuntu mounts are intentionally left in place.

---

## Restarting PostgreSQL

`restart.sh` executes:

```text
pg_ctl -D $PGDATA -l $PGHOME/logfile restart
```

using the same `setpriv` and `LD_PRELOAD` configuration.

This script is useful after PostgreSQL configuration changes.

---

## Checking PostgreSQL Status

`status.sh` executes:

```text
pg_ctl -D $PGDATA status
```

under the same execution environment.

It is also used automatically by the Android startup and shutdown scripts.

---

## Manual Usage

From a rooted Android shell:

```bash
su
cd /data/local
./start-ubuntu.sh
```

The script mounts the required pseudo-filesystems, starts PostgreSQL if necessary, and enters the Ubuntu chroot.

Once inside Ubuntu:

```bash
/scripts/postgres/status.sh
```

can be used to verify PostgreSQL.

To restart it:

```bash
/scripts/postgres/restart.sh
```

To leave the interactive Ubuntu shell:

```bash
exit
```

The Ubuntu environment can then be safely stopped from Android with:

```bash
cd /data/local
./stop-ubuntu.sh
```

---

## File Permissions

The Android control scripts need to be executable:

```bash
chmod 755 /data/local/start-ubuntu.sh
chmod 755 /data/local/stop-ubuntu.sh
```

The PostgreSQL scripts also need execute permission:

```bash
chmod 755 /data/local/ubuntu24/scripts/postgres/*.sh
```

Inside the chroot they appear as:

```text
/scripts/postgres/*.sh
```

---

## Device Consistency

The same script names and directory structure are currently used across the tested Android devices.

This standardization makes administration easier because the operational commands remain consistent even when CPU architecture or device hardware differs.

Device-specific differences should therefore be kept outside these scripts whenever possible.

Examples of device-dependent details include:

- CPU architecture
- 32-bit versus 64-bit userspace
- Android kernel
- required supplementary groups
- PostgreSQL build architecture
- shared-memory compatibility requirements

---

## Integrity of the Extracted Scripts

The scripts currently preserved in this repository were extracted from the working Samsung Galaxy A15 environment.

SHA-256 values at extraction time:

```text
07307437f40902c2f7e91b7f129f4b3bd790a0772ba381ce1cbc2ca6e89ba363  android/start-ubuntu.sh
1f16294c73eb4a73a8ee91df8b59abbb5c45424e05b32b2562163e5214c5ae05  android/stop-ubuntu.sh
634aaed3ebbb14fffc427386e6be3b6e9c6a47bae0eb0398f6640deb27979dba  postgres/restart.sh
ac09d0d0bf68fe1aace71a2cb47de83e73d7be5a0207f51508dd74dab09c9b38  postgres/start.sh
45c344e8aa3aa488b37fc289d141e00064811d8637c4e7b5bca963b90d3d8cc7  postgres/status.sh
508dedce15bf5642a8ccec494b45615271f513fd305d08c6e9e7354117b985ef  postgres/stop.sh
```

The hashes remained identical after transfer to the development desktop.

Changing only the executable permission bits does not change these SHA-256 values because the hashes represent file contents rather than filesystem permission metadata.

---

## Security

These scripts intentionally contain no PostgreSQL passwords, replication credentials, private keys, tokens, or production connection strings.

Do not add real credentials directly to these files when adapting them.

Configuration containing authentication information should be handled separately and excluded from public repositories.

---

## Experimental Status

These scripts represent the configuration used by this experimental project.

They should be reviewed and adapted before use on another device.

In particular, do not assume that:

```text
--groups=1000,3003
```

is appropriate for another Android device.

Verify ownership, group IDs, mount behavior, root implementation, SELinux behavior, Android version, and chroot location before use.
