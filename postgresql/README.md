# PostgreSQL 18.6 on Android with Ubuntu 24.04 Chroot

[Português](README.pt-BR.md)

## Overview

This documentation describes the compilation, installation, and execution of PostgreSQL 18.6 on rooted Android devices using Ubuntu 24.04 LTS in a chroot environment.

The procedures documented here are based on real devices used during the development of this project.

The goal is not merely to present a sequence of commands, but to document the particularities encountered when running PostgreSQL directly on the Android Linux kernel while using a GNU/Linux userspace provided by Ubuntu.

The devices currently used in the project are:

- Samsung Galaxy A15 — ARM64 — primary PostgreSQL server
- Motorola Android One (deen) — ARM64 — PostgreSQL hot standby
- LG K11 Plus — ARMHF/32-bit — experimental node

The same main layout was used on all three devices:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

The PostgreSQL version tested is:

```text
PostgreSQL 18.6
```

---

## Environment architecture

PostgreSQL is not running inside a virtual machine.

Ubuntu uses `chroot` and shares the same Linux kernel used by Android.

Conceptually:

```text
Android device
        |
        +-- Android Linux kernel
                |
                +-- Android userspace
                |
                +-- Ubuntu 24.04 chroot
                        |
                        +-- PostgreSQL 18.6
                        |
                        +-- android-shmem
```

The chroot provides PostgreSQL with a GNU/Linux userspace, libraries, compilation tools, and its own view of the filesystem.

However, chroot does not provide:

- a separate kernel
- a virtual machine
- complete process isolation
- an independent user namespace
- an independent process lifecycle

This distinction is important for understanding several behaviors observed during testing.

---

## Tested environments

### Samsung Galaxy A15

Verified environment:

```text
Ubuntu:       Ubuntu 24.04.4 LTS
Architecture: aarch64 / ARM64
PostgreSQL:   18.6
PostgreSQL:   ELF 64-bit ARM aarch64
Source:       /usr/local/src/postgresql-18.6
Installation: /usr/local/pgsql18
PGDATA:       /usr/local/pgsql18/data
android-shmem: ELF 64-bit ARM aarch64
```

The Galaxy A15 is currently used as the PostgreSQL primary.

On the network used during the experiments:

```text
Galaxy A15
192.168.1.50
PostgreSQL primary
```

### Motorola Android One (deen)

The Motorola is an ARM64 device running the same Ubuntu 24.04 and PostgreSQL 18.6.

It was configured as a hot standby for the Galaxy A15 using PostgreSQL physical streaming replication.

During testing:

```text
Motorola Android One
192.168.1.40
PostgreSQL hot standby
```

Replication:

```text
Galaxy A15                         Motorola
PRIMARY                            HOT STANDBY
192.168.1.50                       192.168.1.40

     WAL streaming
---------------------------------------->
```

was successfully validated.

### LG K11 Plus

The LG represents a particularly interesting case because its installed Android environment uses a 32-bit userspace.

Observed results:

```text
Ubuntu:       Ubuntu 24.04.4 LTS
uname -m:     armv7l
LONG_BIT:     32
PostgreSQL:   18.6
PostgreSQL:   ELF 32-bit ARM EABI5
Source:       /usr/local/src/postgresql-18.6
Installation: /usr/local/pgsql18
PGDATA:       /usr/local/pgsql18/data
android-shmem: ELF 32-bit ARM EABI5
```

PostgreSQL was successfully compiled and executed in this ARMHF/32-bit environment.

This device also revealed a particular issue related to the `__shmctl64` symbol, documented later.

---

## PostgreSQL source code

The PostgreSQL version used in the tests was compiled directly from source code.

The source tree used on the devices is:

```text
/usr/local/src/postgresql-18.6
```

On the LG, for example, the following archive was also preserved:

```text
/usr/local/src/postgresql-18.6.tar.gz
```

The installation prefix was standardized across the devices:

```text
/usr/local/pgsql18
```

This keeps the installation independent from any PostgreSQL packages that may be provided by the Ubuntu distribution.

---

## Actual configuration used for compilation

Rather than reconstructing the configuration options afterward, the project retrieved this information directly from the PostgreSQL installation that was actually installed and running successfully, using:

```bash
/usr/local/pgsql18/bin/pg_config --configure
```

and from the file:

```text
/usr/local/src/postgresql-18.6/config.status
```

The configuration confirmed to have been used was:

```bash
./configure \
  --prefix=/usr/local/pgsql18 \
  --with-openssl \
  --with-libxml \
  --with-libxslt \
  --with-icu
```

The same configuration was confirmed on both the ARM64 Galaxy A15 and the ARMHF/32-bit LG.

The compiler recorded by PostgreSQL is:

```text
gcc
```

---

## Compilation dependencies

In the ARM64 environment used on the Galaxy A15, the following compilation-related packages were identified, among others:

```text
build-essential
bison
flex
gcc
libicu-dev
libreadline-dev
libssl-dev
libxml2-dev
libxslt1-dev
make
pkg-config
zlib1g-dev
```

A typical installation of the dependencies used can be performed with:

```bash
apt update

DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential \
  bison \
  flex \
  libicu-dev \
  libreadline-dev \
  libssl-dev \
  libxml2-dev \
  libxslt1-dev \
  pkg-config \
  zlib1g-dev
```

The exact dependencies may vary depending on the Ubuntu version and any additional options selected during compilation.

---

## Compilation

With the dependencies installed and the source code extracted:

```bash id="x4gjwm"
cd /usr/local/src/postgresql-18.6
```

Configure:

```bash id="t2xj88"
./configure \
  --prefix=/usr/local/pgsql18 \
  --with-openssl \
  --with-libxml \
  --with-libxslt \
  --with-icu
```

Compile:

```bash id="rhvxy4"
make
```

And install:

```bash id="t1pq38"
make install
```

The resulting installation used by the project is located at:

```text id="0veo1j"
/usr/local/pgsql18
```

The version can be confirmed with:

```bash id="6oj4nx"
/usr/local/pgsql18/bin/postgres --version
```

Expected result for this documentation:

```text id="omynof"
postgres (PostgreSQL) 18.6
```

`initdb` was also verified:

```bash id="pl62ol"
/usr/local/pgsql18/bin/initdb --version
```

Observed result:

```text id="hwb1k9"
initdb (PostgreSQL) 18.6
```

---

## PostgreSQL user

In the documented environments, the following configuration was used:

```text
uid=1000(postgres)
gid=1000(postgres)
groups=1000(postgres)
```

The data directory is owned by the PostgreSQL user:

```text
postgres:postgres
```

and uses restricted permissions:

```text
drwx------
```

Example:

```text
/usr/local/pgsql18/data
```

---

## Important note about UID 1000 on Android

Using UID 1000 produces behavior that may initially cause confusion.

Android and the Ubuntu chroot share the same kernel and, consequently, the same process table.

However, tools running inside Ubuntu translate UID numbers using Ubuntu's `/etc/passwd`.

If:

```text id="z77u9f"
UID 1000 = postgres
```

inside Ubuntu, Android processes that also have the numeric UID `1000` may appear in tools such as `ps` under the name:

```text id="6ff5js"
postgres
```

even though those processes have no relation to the PostgreSQL server.

Therefore, in this environment, it is not recommended to identify PostgreSQL processes simply by looking for every process whose displayed user is `postgres`.

A more reliable method is to use:

```text id="e1x1do"
/usr/local/pgsql18/data/postmaster.pid
```

The first number in this file corresponds to the postmaster PID.

For example:

```bash id="wztg5n"
POSTMASTER_PID=$(head -1 /usr/local/pgsql18/data/postmaster.pid)

echo "$POSTMASTER_PID"
```

---

## Why android-shmem is used

During testing, PostgreSQL encountered incompatibilities related to System V shared memory in the Android/chroot environment.

One of the symptoms observed during the investigation was:

```text id="z4h3fm"
shmget: Function not implemented
```

To provide the required compatibility, the project uses a modified version of pelya's `android-shmem` project.

Complete documentation of this modification can be found at:

```text id="v3n6nq"
../android-shmem/
```

The library used by PostgreSQL is installed as:

```text id="a9i2lv"
/usr/local/lib/libandroid-shmem.so
```

---

## LD_PRELOAD

PostgreSQL is started using:

```text id="e5y7kn"
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

This allows certain shared-memory-related calls to be intercepted by the compatibility library.

The script used by the project follows this structure:

```bash id="r8k4wp"
PGHOME=/usr/local/pgsql18
PGDATA=$PGHOME/data
SHMEM=/usr/local/lib/libandroid-shmem.so

setpriv \
  --reuid=postgres \
  --regid=postgres \
  --groups=1000,3003 \
  env LD_PRELOAD=$SHMEM \
  $PGHOME/bin/pg_ctl \
  -D $PGDATA \
  -l $PGHOME/logfile \
  start
```

The actual scripts used by the project can be found at:

```text id="u1p6zs"
../scripts/postgres/
```

---

## Verifying that android-shmem is actually loaded

We do not rely solely on the presence of `LD_PRELOAD` in the script.

During testing, the environment of the postmaster process that was actually running was inspected.

First, obtain the PID:

```bash
POSTMASTER_PID=$(head -1 /usr/local/pgsql18/data/postmaster.pid)
```

Then:

```bash
tr '\0' '\n' < /proc/$POSTMASTER_PID/environ \
  | grep -E '^(LD_PRELOAD|PATH|HOME)='
```

On the Galaxy A15, the following was observed:

```text
HOME=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

On the LG K11 Plus, the following was likewise observed:

```text
HOME=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

Therefore, in both verified environments, the PostgreSQL process effectively inherited the library through `LD_PRELOAD`.

---

## Additional groups used by setpriv

Although:

```bash
id postgres
```

normally shows:

```text
uid=1000(postgres) gid=1000(postgres) groups=1000(postgres)
```

the project scripts start PostgreSQL with:

```text
--groups=1000,3003
```

The supplementary group `3003` is assigned to the process by `setpriv` during startup.

It does not need to appear as a permanent group of the `postgres` user in `/etc/group` for a process started this way to receive the supplementary group.

This detail is specific to the Android environment used in this project and should be taken into account when adapting the scripts to other devices.

---

## dynamic_shared_memory_type

The configuration used in the Android environment includes:

```conf
dynamic_shared_memory_type = mmap
```

During the investigation, there were two occurrences in the configuration file in one of the environments:

```text
dynamic_shared_memory_type = posix
dynamic_shared_memory_type = mmap
```

The effective configuration was adjusted to:

```conf
dynamic_shared_memory_type = mmap
```

This setting relates to PostgreSQL dynamic shared memory and is distinct from the System V compatibility provided through `android-shmem`.

---

# LG K11 Plus specific issue: __shmctl64

The LG K11 Plus uses Ubuntu ARMHF/32-bit.

The PostgreSQL executable was confirmed as:

```text
ELF 32-bit LSB pie executable, ARM, EABI5
```

During the investigation, it was discovered that the PostgreSQL executable references the symbol:

```text
__shmctl64@GLIBC_2.34
```

This was verified with:

```bash
readelf -Ws /usr/local/pgsql18/bin/postgres \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

Among the observed results:

```text
UND shmat@GLIBC_2.4
UND __shmctl64@GLIBC_2.34
UND shmdt@GLIBC_2.4
UND shmget@GLIBC_2.4
```

The original implementation used as the base provided `shmctl`, but the ARMHF adaptation also needed to provide `__shmctl64`.

The following was added to `shmem.c`:

```c
int __shmctl64 (int shmid, int cmd, void *buf)
{
    return shmctl(shmid, cmd, (struct shmid_ds *)buf);
}
```

And `exports.txt` was updated to export:

```text
__shmctl64;
```

After recompilation, the library used on the LG provided:

```text
shmget
shmat
shmdt
shmctl
__shmctl64
```

The following verification:

```bash
readelf -Ws /usr/local/lib/libandroid-shmem.so \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

confirmed that `__shmctl64` was present in the library.

This modification is preserved in the reproducible patch:

```text
../android-shmem/patches/android-shmem-postgresql.patch
```

---

## Another important modification to android-shmem

The upstream code used as the base restricted `shmget()` to:

```c
key == IPC_PRIVATE
```

The relevant original logic was:

```c
if (key != IPC_PRIVATE)
{
    DBG ("%s: key %d != IPC_PRIVATE,  this is not supported", __PRETTY_FUNCTION__, key);
    errno = EINVAL;
    return -1;
}
```

During testing, this restriction was disabled.

In the patch, we intentionally preserved the original code as comments:

```c
//if (key != IPC_PRIVATE)
//{
//    DBG ("%s: key %d != IPC_PRIVATE,  this is not supported", __PRETTY_FUNCTION__, key);
//    errno = EINVAL;
//    return -1;
//}
```

In addition to reproducing the exact experimental modification that was used, keeping the original code visible makes it easier to understand which upstream behavior was modified.

See `../android-shmem/` for the complete explanation.

---

# Management scripts

The project uses standardized scripts across the devices.

Inside Ubuntu:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

On Android:

```text
/data/local/start-ubuntu.sh
/data/local/stop-ubuntu.sh
```

The versions preserved in the repository can be found at:

```text
../scripts/android/
../scripts/postgres/
```

The structure and file names were kept identical across the tested devices to simplify maintenance and reproducibility.

---

## Startup

The normal startup flow is:

```text
Android root
     |
     +-- /data/local/start-ubuntu.sh
               |
               +-- mounts /dev
               +-- mounts /dev/pts
               +-- mounts /proc
               +-- mounts /sys
               |
               +-- checks PostgreSQL status
               |
               +-- starts PostgreSQL if necessary
               |
               +-- opens Bash inside the Ubuntu chroot
```

PostgreSQL is started through:

```text
/scripts/postgres/start.sh
```

---

## Normal shutdown

The normal shutdown procedure uses:

```text id="vlhqns"
/data/local/stop-ubuntu.sh
```

The script:

1. requests PostgreSQL to shut down;
2. verifies that PostgreSQL has actually stopped;
3. only then unmounts the chroot's auxiliary resources.

Conceptually:

```text id="jqfp2z"
stop-ubuntu.sh
       |
       +-- PostgreSQL stop
       |
       +-- waits for shutdown
       |
       +-- confirms server has stopped
       |
       +-- umount /dev/pts
       +-- umount /dev
       +-- umount /proc
       +-- umount /sys
```

This remains the procedure recommended by the project.

---

# PostgreSQL lifecycle and chroot behavior

An important behavior was observed during the experiments.

After PostgreSQL is started through the Ubuntu chroot, exiting Bash with:

```bash id="x20afn"
exit
```

does not stop PostgreSQL.

This happens because terminating the interactive shell does not mean terminating the other processes that were started through that environment.

PostgreSQL continues to exist as a process in the Linux kernel shared with Android.

---

## Experiment: unmounting while PostgreSQL is running

A separate manual test was also performed outside the normal shutdown procedure.

In this experiment:

1. PostgreSQL was started through the chroot;
2. the Ubuntu shell was exited;
3. PostgreSQL was **not** stopped;
4. the chroot's auxiliary mounts were manually unmounted;
5. the database was accessed remotely from an Ubuntu Desktop system.

The auxiliary mounts that were unmounted were:

```text
/dev/pts
/dev
/proc
/sys
```

Even after these mounts were unmounted, the PostgreSQL processes remained active and the server continued responding to remote connections during the test.

Conceptually:

```text
PostgreSQL started
       |
       +-- exit Bash
       |
       +-- unmount /dev/pts
       +-- unmount /dev
       +-- unmount /proc
       +-- unmount /sys
       |
       +-- PostgreSQL processes remain running
       |
       +-- remote connections continue working
```

This is possible because:

```text
/data/local/ubuntu24
```

is not unmounted by these operations.

The main files remain on Android storage:

```text
/data/local/ubuntu24/usr/local/pgsql18
/data/local/ubuntu24/usr/local/pgsql18/data
/data/local/ubuntu24/usr/local/lib/libandroid-shmem.so
```

The test demonstrates an important difference between chroot and virtualization.

**This result is an experimental observation and not an operational recommendation.**

The normal procedure remains to shut down PostgreSQL properly before unmounting the auxiliary resources.

---

# Network access

PostgreSQL was configured to accept connections over the local network.

During testing on the Galaxy A15, the following was confirmed:

```sql
SHOW listen_addresses;
```

Result:

```text
*
```

Authentication configuration must be handled carefully in:

```text
/usr/local/pgsql18/data/pg_hba.conf
```

Do not publish real passwords, password hashes, or configurations containing credentials in this repository.

---

# Streaming replication

PostgreSQL physical streaming replication was configured between:

```text
Galaxy A15                         Motorola Android One

192.168.1.50                       192.168.1.40

PRIMARY                            HOT STANDBY
PostgreSQL 18.6                    PostgreSQL 18.6
ARM64                              ARM64

              WAL
---------------------------------------->
```

On the primary, settings compatible with replication were confirmed:

```text
wal_level = replica
max_wal_senders = 10
listen_addresses = *
```

A dedicated user with the following attribute was also created:

```text
Replication
```

Real credentials are not included in the repository.

---

## Creating the standby

The standby was created using `pg_basebackup`.

The workflow used was:

```text
PRIMARY
192.168.1.50
      |
      | pg_basebackup
      |
      v
HOT STANDBY
192.168.1.40
```

After `pg_basebackup`, the following file was created:

```text
standby.signal
```

and the connection configuration for the primary was written by PostgreSQL.

**Never publish the actual `postgresql.auto.conf` file when it contains the replication password.**

Always use fictitious values in examples.

---

## Replication confirmed

On the primary, `pg_stat_replication` showed the Motorola in the following state:

```text
state      = streaming
sync_state = async
```

During validation, the following LSNs reached the same value:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

On the standby:

```sql
SELECT pg_is_in_recovery();
```

returned:

```text
t
```

And:

```sql
SELECT status, sender_host, sender_port
FROM pg_stat_wal_receiver;
```

confirmed:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

---

## Real replication test

A row was inserted on the Galaxy A15 primary containing:

```text
written on the A15 and replicated to the Motorola
```

and was subsequently queried successfully on the Motorola standby.

This confirmed the complete replication flow:

```text
INSERT on A15
     |
     +-- WAL
           |
           +-- streaming
                  |
                  +-- replay on Motorola
                           |
                           +-- SELECT on standby
```

---

# Experimental query strategy

The project is investigating a strategy in which the Galaxy A15 remains the primary node for a large portion of the queries as well.

The motivation is practical: many Official Gazettes are published during the night or early morning, a period when user load tends to be lower.

Therefore, the A15 can primarily handle writes during this period while remaining available to serve a large number of queries during the day.

The Motorola does not need to receive every query simply because it is a replica.

The strategy being investigated is:

```text
Query
   |
   v
Galaxy A15
PRIMARY
   |
   +-- capacity available --> SELECT on A15
   |
   +-- SELECT bottleneck
             |
             +-- new query
                     |
                     v
               Motorola
               HOT STANDBY
```

The future goal is to use the replica as additional capacity when there is read contention or a read bottleneck on the primary.

This distribution policy is still experimental and will be evaluated through dedicated benchmarks.

---

# Insertion tests

Bulk insert operations were also performed during the experiments.

In one remote test, the Motorola connected to PostgreSQL running on the A15 and inserted 100,000 records in a single transaction.

Approximately the following results were observed:

```text
INSERT 100000: 920.761 ms
COMMIT:          29.499 ms
```

This result belongs to the experimental environment used at that time and should not be interpreted as a universal benchmark.

Other tests used millions of records and `COPY`.

Detailed results will be organized under:

```text
../benchmarks/
```

---

# Security

This project documents real systems, but the public repository must not contain real credentials.

Never publish:

```text
PostgreSQL passwords
replication user password
primary_conninfo containing a password
actual postgresql.auto.conf containing credentials
private keys
tokens
Android credentials
personal data
production database backups
```

Before adding files to Git, search for sensitive information.

For example:

```bash
grep -RniE \
'password|passwd|senha|secret|token|private.key|BEGIN.*PRIVATE|primary_conninfo' \
. \
--exclude-dir=.git
```

Manually review every result before committing.

---

# What has been demonstrated so far

The experiments have demonstrated:

- PostgreSQL 18.6 compiled from source in an Ubuntu 24.04 chroot
- execution on ARM64 Android
- execution on ARMHF/32-bit Android
- 64-bit ELF PostgreSQL on the Galaxy A15
- 32-bit ELF PostgreSQL on the LG K11 Plus
- effective use of `LD_PRELOAD`
- loading of `libandroid-shmem.so`
- adaptation of `shmget()` to support keys other than `IPC_PRIVATE`
- `__shmctl64` compatibility in the ARMHF/32-bit environment
- startup and shutdown through standardized scripts
- PostgreSQL access over the local network
- remote inserts
- high-volume data ingestion
- use of `COPY`
- ARM64 → ARM64 physical streaming replication
- hot standby on an Android device
- queries on the replica
- persistence of PostgreSQL processes after exiting the chroot shell
- observed persistence after manually unmounting the chroot's auxiliary mounts

---

# What still needs to be investigated

Planned tests include:

- formal SELECT benchmarks
- concurrent queries
- hundreds of simultaneous connections
- A15 versus Motorola latency
- automatic read overflow policy
- impact of queries on the primary during writes
- CPU utilization
- RAM utilization
- storage I/O
- temperature
- thermal throttling
- power consumption
- long-term stability
- behavior after Wi-Fi loss
- streaming replication recovery
- device reboots
- behavior after Android suspension
- differences between manufacturers and Android kernels

---

# Experimental status

This project is experimental.

Successfully running PostgreSQL on Android smartphones does not mean that every device is suitable for use as a production server.

Behavior may vary depending on:

```text id="ih45w4"
manufacturer
model
SoC
architecture
Android
kernel
root
SELinux
32/64-bit userspace
RAM
storage
temperature
power management
Wi-Fi
```

The purpose of this repository is to provide reproducible results and a technical starting point for others interested in exploring PostgreSQL, Android, ARM, chroot, and distributed computing.

---

# Related documentation

See also:

```text id="5c46de"
../README.pt-BR.md
../chroot/README.pt-BR.md
../android-shmem/README.pt-BR.md
../scripts/README.pt-BR.md
```

For the English version:

```text id="tnl2hg"
README.md
```

---

# Conclusion

The experiments show that PostgreSQL 18.6 can be compiled and run in an Ubuntu 24.04 chroot hosted on Android, both on ARM64 and in the tested ARMHF/32-bit environment.

The shared memory compatibility provided by the modified `android-shmem` library was an essential part of the implementation.

The Galaxy A15 and Motorola also demonstrated that two ARM64 Android devices can operate as a PostgreSQL primary and hot standby using physical streaming replication.

The LG K11 Plus demonstrated that the experiment can also be extended to an ARMHF/32-bit userspace, requiring an additional adaptation related to `__shmctl64`.

Beyond database operation itself, the experiments also helped demonstrate an important characteristic of the chroot model: PostgreSQL is started using the Ubuntu userspace, but its processes continue to belong to the Linux kernel shared with Android. Exiting the chroot shell does not imply shutting down the server.

The repository will continue documenting not only successful results, but also limitations, failures, architectural differences, and the procedures required to reproduce the environment.
