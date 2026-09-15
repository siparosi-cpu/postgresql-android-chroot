# PostgreSQL 18 on Rooted Android with Ubuntu 24.04 Chroot

[Português (Brasil)](README.pt-BR.md)

## Overview

This project documents a practical experiment running PostgreSQL 18.6,
compiled from source, inside an Ubuntu 24.04 chroot environment on rooted
Android devices.

The project started as an investigation into whether Android smartphones
could be used as real PostgreSQL nodes for data processing, storage,
replication, and read workloads.

The result is a working small PostgreSQL cluster using Android smartphones.

The currently tested architecture includes:

- Samsung Galaxy A15 as the PostgreSQL primary server
- Motorola Android One (deen) as an ARM64 PostgreSQL hot standby/read replica
- LG K11 Plus as an experimental ARMHF/32-bit processing worker
- Ubuntu 24.04 running inside Android chroot environments
- PostgreSQL 18.6 compiled from source
- Modified `android-shmem` compatibility library
- PostgreSQL streaming replication between Android ARM64 devices
- Remote PostgreSQL clients over a local network
- Bulk insertion and storage performance experiments

This repository documents not only the final configuration, but also the
technical problems encountered, failed approaches, source-code modifications,
tests, and reasoning that led to the working implementation.

---

## Why This Project Exists

Running PostgreSQL inside a traditional Linux distribution is straightforward.

Running it inside a Linux chroot hosted by Android is different.

Although Android uses the Linux kernel, its userspace and kernel configuration
can differ significantly from a conventional GNU/Linux system.

One of the main problems encountered during this experiment was shared-memory
support expected by PostgreSQL.

A simple test initially returned:

```text
shmget: Function not implemented

To work around this limitation, this project uses and modifies the
android-shmem compatibility library originally developed by pelya.

The modifications and tests used in this project will be documented in detail
in this repository.

Current Architecture

                         Local Network
                              |
                +-------------+-------------+
                |                           |
                v                           v
        Samsung Galaxy A15          Motorola Android One
        Android / Root              Android / Root
        Ubuntu 24.04 chroot         Ubuntu 24.04 chroot
        PostgreSQL 18.6             PostgreSQL 18.6
        ARM64                       ARM64

        PRIMARY                     HOT STANDBY
        192.168.1.50  ----------->  192.168.1.40
                     WAL streaming

        INSERT / UPDATE             SELECT
        SELECT                      Read replica


A third tested device is currently used as an experimental processing worker:

LG K11 Plus
MediaTek MT6750
Android userspace: 32-bit
Kernel reports: armv7l
Ubuntu 24.04: armhf
PostgreSQL 18.6: 32-bit

The LG device is not currently used as a physical PostgreSQL replica.

PostgreSQL Streaming Replication

Physical streaming replication between the Samsung Galaxy A15 and Motorola
Android One has been successfully tested.

On the primary server:

client_addr = 192.168.1.40
state       = streaming
sync_state  = async

During validation, the WAL positions reached the same LSN for:

sent_lsn
write_lsn
flush_lsn
replay_lsn

On the Motorola standby:

SELECT pg_is_in_recovery();

returned:

t

The WAL receiver reported:

status      = streaming
sender_host = 192.168.1.50
sender_port = 5432

A test row inserted on the Galaxy A15 primary was successfully read from the
Motorola standby.

Shared Memory Compatibility

PostgreSQL expects shared-memory functionality that was not directly available
in the tested Android/chroot environment.

The project uses:

https://github.com/pelya/android-shmem

During testing, the original implementation rejected shared-memory keys other
than IPC_PRIVATE.

The relevant original logic was:

if (key != IPC_PRIVATE)
{
    errno = EINVAL;
    return -1;
}

The experimental implementation used for this project was modified to allow
the shared-memory keys required during PostgreSQL initialization.

Additional compatibility work was required on the ARMHF/32-bit environment,
where binaries referenced:

__shmctl64@GLIBC_2.34

while the original compatibility library exported:

shmctl

The complete modifications, patches, explanation, and reproducible tests will
be included under the android-shmem/ directory.

Shared Memory Validation

shmget OK
shmat OK
write/read OK
shmdt OK
IPC_RMID OK

PostgreSQL initialization subsequently completed successfully inside the
Android-hosted Ubuntu chroot.

The PostgreSQL configuration used in this environment includes:

dynamic_shared_memory_type = mmap

PostgreSQL Build

The PostgreSQL version currently tested is:

PostgreSQL 18.6

The installation prefix used in the Android chroot environments is:

/usr/local/pgsql18

Source code is built directly inside Ubuntu 24.04 running in the chroot.

Detailed build dependencies, configure options, compilation steps, and
architecture-specific notes are documented separately.

Ubuntu Environment

The tested Linux environment is based on:

Ubuntu 24.04 LTS

Ubuntu runs as a chroot and therefore shares the Android device's Linux kernel.

This is not a virtual machine.

Conceptually:

Android device
      |
      +-- Linux kernel
             |
             +-- Android userspace
             |
             +-- Ubuntu 24.04 chroot
                     |
                     +-- PostgreSQL 18.6

This distinction is important when investigating kernel features and shared
memory behavior.

Project Goals

The project investigates whether inexpensive or otherwise unused Android
devices can participate in PostgreSQL and distributed-processing workloads.

Areas being investigated include:

PostgreSQL on rooted Android
ARM64 PostgreSQL nodes
ARMHF PostgreSQL experiments
shared-memory compatibility
bulk data ingestion
read performance
PostgreSQL streaming replication
hot standby queries
distributed processing workers
concurrent SELECT workloads
storage performance
network performance
thermal behavior
long-running stability
What Has Been Successfully Tested

So far, the project has successfully demonstrated:

Ubuntu 24.04 chroot on rooted Android
PostgreSQL 18.6 compiled from source
PostgreSQL running on Android ARM64
PostgreSQL running on an ARMHF/32-bit Android environment
shared-memory compatibility using a modified android-shmem
PostgreSQL initialization inside the chroot
PostgreSQL network access from external computers
bulk inserts
COPY-based data ingestion
PostgreSQL physical streaming replication between two ARM64 Android devices
hot standby operation
SELECT queries on the Android read replica
Experimental Status

This is an experimental research project.

It should not currently be interpreted as a recommendation to use arbitrary
Android smartphones as production PostgreSQL servers.

Results may depend on:

Android version
Linux kernel configuration
CPU architecture
32-bit vs 64-bit userspace
rooting method
SELinux configuration
device manufacturer
storage technology
thermal limits
available RAM

The repository distinguishes between experimentally verified results and
future work.

Planned Tests

Future experiments include:

concurrent SELECT benchmarks
query latency measurements
hundreds of simultaneous queries
primary-to-replica read overflow
additional ARM64 Android replicas
CPU utilization measurements
RAM utilization
storage I/O measurements
thermal throttling
power consumption
long-duration PostgreSQL operation
replica recovery after network interruption
Android reboot recovery

Repository Structure

docs/
    en/
    pt-BR/

scripts/
    android/
    postgres/

android-shmem/
    patches/
    tests/

benchmarks/
    results/
    sql/

diagrams/

Detailed English and Brazilian Portuguese documentation will be maintained
side by side.

Upstream Project

Shared-memory compatibility work in this project is based on the
android-shmem project by pelya:

https://github.com/pelya/android-shmem

Original copyrights and licensing requirements of upstream projects remain
applicable.

This repository will keep project-specific modifications separate and
documented as patches whenever possible.

Security

Do not copy real database passwords, replication credentials, private keys,
device identifiers, or production configuration files into a public
repository.

Example configurations in this project use placeholder credentials.

Contributing

This project is being published so that other developers interested in
PostgreSQL, Android, ARM systems, chroot environments, and distributed
computing can reproduce the experiments, report results on other devices, and
improve the approach.

Issues, technical corrections, reproducible test results, and contributions
are welcome.

Status

Experimental, functional, and under active documentation and testing.

```text
