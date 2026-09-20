# PostgreSQL 18 on Rooted Android with Ubuntu 24.04 Chroot

[Português (Brasil)](README.pt-BR.md)

## Overview

This project documents a practical experiment running PostgreSQL 18.6, compiled from source, inside Ubuntu 24.04 chroot environments on rooted Android devices.

The project started as an investigation into whether Android smartphones could be used as real PostgreSQL nodes for data processing, storage, replication, and read workloads.

The result is a working small PostgreSQL cluster using Android smartphones.

The currently tested architecture includes:

- Samsung Galaxy A15 as the PostgreSQL primary server
- Motorola Android One (deen) as an ARM64 PostgreSQL hot standby/read replica
- LG K11 Plus as an experimental ARMHF/32-bit PostgreSQL and processing node
- Ubuntu 24.04 running inside Android chroot environments
- PostgreSQL 18.6 compiled from source
- Modified `android-shmem` compatibility library
- PostgreSQL physical streaming replication between Android ARM64 devices
- Remote PostgreSQL clients over a local network
- Bulk insertion and `COPY` performance experiments

This repository documents not only the final configuration, but also the technical problems encountered, failed approaches, source-code modifications, tests, and reasoning that led to the working implementation.

---

## Why This Project Exists

Running PostgreSQL inside a traditional Linux distribution is straightforward.

Running it inside a Linux chroot hosted by Android presents additional challenges.

Although Android uses the Linux kernel, its userspace and kernel configuration can differ significantly from a conventional GNU/Linux system.

One of the main problems encountered during this experiment was System V shared-memory compatibility.

A simple test program initially returned:

```text
key=74565 size=4096
shmget: Function not implemented
```

The same program, when executed with the modified `android-shmem` compatibility library through `LD_PRELOAD`, successfully created, attached, used, detached, and removed the shared-memory segment.

This compatibility layer became an important part of getting PostgreSQL running successfully in the tested Android/chroot environments.

---

## Current Architecture

```text
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
```

The Galaxy A15 is currently the primary PostgreSQL node.

The Motorola Android One is an asynchronous physical streaming replica and can be used for read-only queries while operating as a hot standby.

The design goal is not to leave the more capable primary device idle. During normal daytime operation, the A15 can continue serving read queries. The Motorola replica can provide additional read capacity when required.

Most bulk ingestion is expected to occur during periods of lower interactive query activity.

---

## Experimental LG K11 Plus Node

A third Android device has also been tested:

```text
LG K11 Plus
Android 7.1.2
MediaTek platform
Android userspace: 32-bit
Kernel reports: armv7l
Ubuntu 24.04 chroot: armhf
PostgreSQL 18.6: 32-bit
```

PostgreSQL 18.6 was successfully compiled and initialized on this device after resolving shared-memory compatibility issues.

The LG K11 Plus is not currently part of the physical replication topology. It is being treated as an experimental processing/PostgreSQL node while additional ARM64 devices are considered for the cluster.

---

## PostgreSQL Streaming Replication

Physical streaming replication between the Samsung Galaxy A15 primary and the Motorola Android One standby has been successfully tested.

On the primary server, `pg_stat_replication` reported:

```text
client_addr  = 192.168.1.40
state        = streaming
sync_state   = async
```

During validation, the following WAL positions reached the same LSN:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

On the Motorola standby:

```sql
SELECT pg_is_in_recovery();
```

returned:

```text
t
```

The standby's `pg_stat_wal_receiver` reported:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

A test row inserted on the Galaxy A15 primary was successfully replicated and read from the Motorola standby.

This confirmed end-to-end physical streaming replication between the two Android-hosted PostgreSQL installations.

---

## The Shared Memory Problem

PostgreSQL depends on shared-memory facilities provided by the operating system.

Inside the tested Android/chroot environment, a direct System V shared-memory test initially failed:

```text
shmget: Function not implemented
```

This was not a PostgreSQL SQL-level problem. It occurred at the operating-system compatibility layer.

The project therefore investigated the `android-shmem` project originally developed by pelya:

https://github.com/pelya/android-shmem

The library provides userspace compatibility implementations for System V shared-memory functions using mechanisms available in Android/Linux environments.

---

## `android-shmem` Compatibility Work

The test program uses the traditional System V shared-memory API:

```c
shmget(...)
shmat(...)
shmdt(...)
shmctl(...)
```

Without the compatibility library:

```text
shmget: Function not implemented
```

With the modified library loaded:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so ./test-shm-key
```

the test successfully progressed through shared-memory allocation and mapping.

An example successful run included:

```text
shmget OK
shmat OK
write/read: android-shmem funcionando
shmdt OK
IPC_RMID OK
```

The project-specific modifications and reproducible test programs will be kept under:

```text
android-shmem/
├── patches/
└── tests/
```

---

## ARMHF / glibc `shmctl` Compatibility

An additional issue appeared in the ARMHF/32-bit Ubuntu environment.

Inspection of the test executable showed:

```text
shmget@GLIBC_2.4
shmat@GLIBC_2.4
__shmctl64@GLIBC_2.34
shmdt@GLIBC_2.4
```

while the compatibility library exported:

```text
shmget
shmat
shmdt
shmctl
```

This distinction was important because intercepting `shmctl` alone did not necessarily intercept a binary calling the glibc symbol:

```text
__shmctl64@GLIBC_2.34
```

Compatibility work was therefore required for this 32-bit environment.

After the changes, the test completed successfully through:

```text
shmget
shmat
write/read
shmdt
shmctl(IPC_RMID)
```

The exact source modifications will be documented separately rather than hidden inside a precompiled binary.

---

## PostgreSQL Initialization

After the shared-memory compatibility work, PostgreSQL `initdb` successfully completed inside the Android-hosted Ubuntu environment.

During initialization, the compatibility library handled multiple shared-memory allocations.

The initialization finished with:

```text
performing post-bootstrap initialization ... ok
syncing data to disk ... ok
```

followed by:

```text
Success. You can now start the database server using:

    /usr/local/pgsql18/bin/pg_ctl -D /usr/local/pgsql18/data -l logfile start
```

This was an important milestone because it demonstrated that PostgreSQL could initialize a complete database cluster in the tested environment.

---

## Dynamic Shared Memory

The PostgreSQL configuration used in the tested environment includes:

```conf
dynamic_shared_memory_type = mmap
```

Verification through PostgreSQL returned:

```sql
SHOW dynamic_shared_memory_type;
```

```text
 dynamic_shared_memory_type
----------------------------
 mmap
```

The `android-shmem` compatibility work and PostgreSQL's `dynamic_shared_memory_type = mmap` configuration address different shared-memory mechanisms and should not be treated as the same setting.

---

## PostgreSQL Build

The PostgreSQL version currently tested on the Android devices is:

```text
PostgreSQL 18.6
```

The installation prefix used in the Android chroot environments is:

```text
/usr/local/pgsql18
```

PostgreSQL was compiled from source inside Ubuntu 24.04 running in the Android chroot.

One verified build reported:

```text
PostgreSQL 18.6 on armv7l-unknown-linux-gnueabihf,
compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0,
32-bit
```

Detailed build dependencies, `configure` options, compilation steps, and architecture-specific notes will be documented separately.

---

## Ubuntu 24.04 Chroot

Ubuntu 24.04 LTS is used as the GNU/Linux userspace environment.

Ubuntu runs inside a chroot hosted by Android and therefore uses the Android device's existing Linux kernel.

It is not a virtual machine.

Conceptually:

```text
Android smartphone
        |
        +-- Linux kernel
        |
        +-- Android userspace
        |
        +-- Ubuntu 24.04 chroot
                |
                +-- GNU/Linux userspace
                |
                +-- PostgreSQL 18.6
```

This distinction is important.

A chroot changes the apparent filesystem root for processes, but it does not provide a separate kernel. Therefore, kernel features available to PostgreSQL are ultimately determined by the Android device's running kernel and configuration.

---

## Starting PostgreSQL with the Chroot

The Android-side chroot startup process was modified so PostgreSQL can be started automatically when entering the Ubuntu environment.

The project uses dedicated PostgreSQL helper scripts:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

The Android chroot startup and shutdown scripts will also be documented.

During shutdown, PostgreSQL is stopped before the Ubuntu bind mounts are unmounted. This avoids abruptly dismantling the chroot filesystem while the database server is still running.

Example and sanitized scripts will be published under:

```text
scripts/android/
scripts/postgres/
```

---

## Network Access

PostgreSQL has been successfully accessed from another Ubuntu desktop on the same local network.

For testing, PostgreSQL listened on the network interface and remote clients connected to the Android-hosted server.

The project will provide sanitized `postgresql.conf` and `pg_hba.conf` examples rather than publishing production credentials.

Network addresses shown in this repository are private RFC1918 LAN addresses used only to describe the test topology.

---

## Bulk Insert Tests

Bulk data insertion has been tested remotely from an Ubuntu desktop to PostgreSQL running on the Android device.

One SQL test inserted:

```sql
INSERT INTO teste_insercao (origem, valor)
SELECT 'desktop_ubuntu', g
FROM generate_series(1, 1000000) AS g;
```

A measured run reported:

```text
Rows:         1,000,000
Execute time: 24 seconds
```

This result represents a specific experimental run and should not be interpreted as a general PostgreSQL or Android benchmark.

Hardware state, storage, Wi-Fi conditions, PostgreSQL configuration, thermal conditions, and other factors can affect performance.

---

## `COPY` Tests

Bulk ingestion was also tested from the Ubuntu desktop using PostgreSQL `\copy`.

For one million generated rows:

```bash
awk 'BEGIN {
  for (i=1; i<=1000000; i++)
    print "desktop_ubuntu," i
}' | \
/path/to/psql \
  -h SERVER_IP \
  -U postgres \
  -d postgres \
  -c "\copy teste_insercao(origem,valor) FROM STDIN WITH (FORMAT csv)"
```

The result was:

```text
COPY 1000000

real    0m32.513s
user    0m0.702s
sys     0m0.129s
```

A five-million-row test returned:

```text
COPY 5000000

real    1m56.230s
user    0m3.520s
sys     0m0.420s
```

These are observed experimental results, not controlled cross-platform benchmark claims.

More rigorous benchmark methodology will be added under `benchmarks/`.

---

## Intended Workload

The project was motivated by a real data-processing scenario involving large numbers of records that are ingested primarily in batches.

The expected workload is read-heavy after ingestion.

The current architectural idea is therefore:

```text
Lower interactive activity
        |
        +-- bulk ingestion
        +-- database maintenance
        +-- replication

Higher interactive activity
        |
        +-- primary serves SELECT queries
        +-- standby remains available for read scaling
        +-- additional queries can be directed to replicas when useful
```

The project does not currently claim automatic PostgreSQL query load balancing between the phones.

Any routing of read traffic between primary and standby requires an external routing/load-balancing layer or application logic and will be investigated separately.

---

## What Has Been Successfully Tested

The project has so far demonstrated:

- rooted Android devices hosting Ubuntu 24.04 chroot environments
- PostgreSQL 18.6 compiled from source
- PostgreSQL running on ARM64 Android devices
- PostgreSQL running in an ARMHF/32-bit Android environment
- System V shared-memory compatibility through a modified `android-shmem`
- successful `initdb`
- PostgreSQL server startup and shutdown
- remote PostgreSQL connections over Wi-Fi/LAN
- bulk SQL inserts
- `COPY`-based data ingestion
- PostgreSQL physical streaming replication between two ARM64 Android devices
- asynchronous replication
- hot standby operation
- successful SELECT queries on the Android standby
- automatic PostgreSQL startup as part of the chroot startup workflow
- controlled PostgreSQL shutdown before chroot unmounting

---

## Experimental Status

This is an experimental research and engineering project.

It should not currently be interpreted as a recommendation to use arbitrary Android smartphones as production PostgreSQL servers.

Results may depend on:

- Android version
- Linux kernel configuration
- CPU architecture
- 32-bit vs. 64-bit userspace
- rooting method
- SELinux configuration
- device manufacturer
- storage technology
- available RAM
- Wi-Fi/network quality
- thermal limits
- battery and power-management behavior

Long-running durability, failure recovery, storage wear, thermal behavior, and production-grade high availability require considerably more testing.

---

## Planned Tests

Future experiments include:

- concurrent SELECT benchmarks
- query latency measurements
- hundreds of simultaneous queries
- primary and standby read-load comparison
- read-routing/load-balancing experiments
- additional ARM64 Android replicas
- CPU utilization measurements
- RAM utilization measurements
- storage I/O measurements
- network throughput measurements
- thermal throttling
- power consumption
- long-duration PostgreSQL operation
- replica recovery after network interruption
- recovery after Android reboot
- replication lag under write load
- behavior while the Android device is charging
- additional Android models and SoCs

---

## Future Direction: Android Device Cluster

One of the future directions of this project is to investigate the use of multiple physical Android devices working together as a low-cost distributed PostgreSQL infrastructure.

The current architecture already provides an experimental foundation for this evolution, with PostgreSQL running natively for the ARM architecture inside an Ubuntu 24.04 chroot and physical streaming replication between Android devices.

The future goal is to expand the experiments toward an architecture composed of different roles, including:

- one Android device acting as the PostgreSQL primary server;
- one or more ARM64 devices acting as hot standbys and read servers;
- additional devices acting as data processing and ingestion nodes;
- distribution of read queries between the primary and replicas;
- evaluation of different routing and load-balancing strategies;
- comparison of communication between devices using Wi-Fi and Ethernet;
- testing the behavior of the system during failures or temporary node disconnections;
- addition of new Android devices to evaluate horizontal expansion of the architecture.

The intention is not to claim that the current configuration constitutes a complete or production-ready PostgreSQL cluster. The goal is to experimentally investigate how far Android smartphones can cooperate as nodes of a PostgreSQL infrastructure, documenting performance, limitations, failures, and solutions found on real hardware.

As new devices and experiments are added, the results will be documented in this repository.

---

## Repository Structure

```text
docs/
├── en/
└── pt-BR/

scripts/
├── android/
└── postgres/

android-shmem/
├── patches/
└── tests/

benchmarks/
├── results/
└── sql/

diagrams/
```

Detailed documentation will be maintained in both English and Brazilian Portuguese.

---

## Upstream Project

The shared-memory compatibility work in this project is based on the `android-shmem` project by pelya:

https://github.com/pelya/android-shmem

Original copyright and licensing requirements of upstream projects remain applicable.

Project-specific modifications will be documented clearly and, whenever practical, distributed as patches rather than obscured inside binary files.

Before publishing derived source code, the applicable upstream license will be reviewed and preserved.

---

## Security

Never copy real database passwords, replication credentials, private keys, authentication tokens, or other secrets into a public repository.

Configuration examples in this repository will use placeholder credentials such as:

```text
SERVER_IP
REPLICATION_USER
REPLICATION_PASSWORD
```

Production `postgresql.auto.conf`, `.pgpass`, private keys, tokens, and credential files must not be committed.

---

## Reproducibility

One of the primary goals of this repository is reproducibility.

Whenever possible, documentation will distinguish between:

- commands actually executed
- observed output
- device-specific configuration
- modifications required for compatibility
- experimental conclusions
- ideas that have not yet been tested

This distinction is especially important because Android kernels and userspaces vary substantially between manufacturers and devices.

---

## Contributing

This project is being published so that developers interested in PostgreSQL, Android, ARM systems, Linux chroot environments, shared-memory compatibility, and distributed computing can reproduce the experiments on other hardware.

Useful contributions include:

- results from additional Android devices
- kernel and architecture compatibility reports
- corrections to the shared-memory compatibility layer
- PostgreSQL build reports
- benchmark results with documented methodology
- replication experiments
- documentation improvements
- reproducible bug reports

Issues and pull requests will be welcome once the repository is made public.

---

## Status

**Experimental — functional and under active documentation and testing.**
