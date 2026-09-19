# PostgreSQL 18.6 Benchmarks on Android

[Português (Brasil)](README.pt-BR.md)

## Overview

This document presents experimental benchmarks of PostgreSQL 18.6 running on rooted Android devices using Ubuntu 24.04 in a chroot environment.

The tests are part of the `postgresql-android-chroot` project and are intended to evaluate, on real Android hardware, PostgreSQL behavior in scenarios involving remote ingestion of large data volumes and physical streaming replication.

The results presented here correspond to the actual runs performed in the test environment described in this document. They should not be interpreted as universal benchmarks of PostgreSQL, Android, or the devices used.

## Objectives

The benchmarks were performed to evaluate:

- remote ingestion using `COPY FROM STDIN`;
- behavior with 100 thousand, 1 million, 10 million, and 20 million rows;
- observed differences between different devices acting as clients;
- PostgreSQL behavior on the Samsung Galaxy A15 as the primary server;
- observed impact during runs with active physical replication;
- WAL position advancement during the loads;
- checkpoint activity during larger loads;
- the Motorola's ability to recover from replication lag;
- WAL retention behavior during standby interruptions;
- the practical feasibility of using Android devices as PostgreSQL nodes.

## Environment Architecture

The Samsung Galaxy A15 was used as the primary PostgreSQL server.

The Motorola Android One XT1941-3 was used in two different roles:

1. remote client during benchmarks without replication;
2. ARM64 physical standby during benchmarks with active replication.

The LG K11 Plus was used as an ARMHF/32-bit remote client.

An Ubuntu Desktop computer was used as the reference client for the remote loads.

The logical architecture of the tests was:

```text
Without replication:

Ubuntu Desktop ───────┐
                      │
Motorola ─────────────┼── COPY FROM STDIN ──> Samsung Galaxy A15
                      │                       PostgreSQL 18.6
LG K11 Plus ──────────┘


With replication:

Ubuntu Desktop
      │
      │ COPY FROM STDIN
      ▼
Samsung Galaxy A15
PostgreSQL 18.6
Primary
      │
      │ Physical Streaming Replication
      ▼
Motorola XT1941-3
PostgreSQL 18.6
Hot Standby
```

## PostgreSQL Version

The primary server and standby used PostgreSQL 18.6 compiled from source.

Installation prefix:

/usr/local/pgsql18

Data directory:

/usr/local/pgsql18/data

On the Android devices, PostgreSQL ran inside Ubuntu 24.04 in a chroot environment sharing the Android kernel.

The android-shmem compatibility library was loaded through:

LD_PRELOAD=/usr/local/lib/libandroid-shmem.so

The following setting was used for dynamic shared memory:

dynamic_shared_memory_type = mmap


## Table Used in the Benchmark

The loads used a table without a primary key and without additional indexes, allowing sequential ingestion through COPY to be evaluated without index maintenance overhead.

CREATE TABLE benchmark_copy
(
    id bigint NOT NULL,
    origem text NOT NULL,
    numero_processo varchar(30) NOT NULL,
    nome text NOT NULL,
    texto text NOT NULL,
    criado_em timestamptz NOT NULL DEFAULT now()
);

Before each valid run, the table was emptied with:

TRUNCATE TABLE benchmark_copy;

## Row Generation and Transmission

The rows were generated on the client itself using awk and sent directly to psql through a pipe.

Simplified example:

awk '...' |
psql \
    -h PRIMARY_IP \
    -p 5432 \
    -U postgres \
    -d postgres \
    -c "COPY benchmark_copy
        (id, origem, numero_processo, nome, texto)
        FROM STDIN;"

No intermediate CSV file was created.

Consequently, the rows were produced and transmitted as a stream:

awk
 │
 ▼
pipe
 │
 ▼
psql
 │
 ▼
TCP/IP
 │
 ▼
PostgreSQL
 │
 ▼
COPY FROM STDIN

## Interpretation of the Measured Time

Load times were collected with GNU time.

Example:

real
user
sys
cpu
max_rss_kb

The real value represents the time observed by the client for the complete pipeline.

Therefore, the numbers presented in this document are end-to-end benchmarks.

They include, among other factors:

row generation by awk;
psql processing;
network transmission;
PostgreSQL protocol processing;
COPY execution;
WAL generation;
storage activity;
checkpoints occurring during the interval;
transaction commit;
and, when enabled, activity associated with replication.

For this reason, differences between runs with and without replication should not automatically be interpreted as the isolated cost of replication.

## Client Memory

Because the rows were continuously generated and transmitted through a pipe, the client did not need to keep the entire dataset in memory.

This explains the relatively small max_rss_kb values observed even with loads of 10 and 20 million rows.

## WAL

WAL advancement was calculated using LSN positions observed before and after the loads.

Example:

SELECT pg_wal_lsn_diff(
    pg_current_wal_lsn(),
    'INITIAL_LSN'
);

This value should be interpreted as:

advancement of the cluster WAL position during the benchmark interval.

It does not necessarily represent the exact amount of WAL produced exclusively by the benchmark_copy table.

Other cluster activity occurring within the same interval may also contribute to WAL position advancement.

## Row Validation

After the larger loads, checks such as the following were performed:

SELECT
    count(*) AS rows,
    min(id) AS min_id,
    max(id) AS max_id,
    count(DISTINCT id) AS distinct_ids
FROM benchmark_copy;

pg_stat_database.tup_inserted was also used as an additional check of the number of tuples inserted into the postgres database during the observed interval.

During replication tests, the rows were also queried directly on the Motorola standby.

## Checkpoints

In PostgreSQL 18, checkpoint activity was monitored through:

SELECT
    num_timed,
    num_requested,
    num_done,
    write_time,
    sync_time,
    buffers_written
FROM pg_stat_checkpointer;

Snapshots were collected before and after the larger loads to allow comparison of the differences observed during each run.

The following sections present the experimental results obtained with each client, followed by the tests performed with active physical replication.

# Results Without Replication

In this first series, PostgreSQL on the Samsung Galaxy A15 received the loads without a connected standby.

The `pg_stat_replication` query returned zero connections during the valid tests in this series.

Three clients were used:

- Ubuntu Desktop;
- Motorola Android One XT1941-3;
- LG K11 Plus.

Each client executed loads of:

```text
100,000
1,000,000
10,000,000
20,000,000
```

## Consolidated Throughput

The table below presents the end-to-end throughput calculated from the real time observed on each client.

| Rows | Desktop → A15 | Motorola → A15 | LG K11 Plus → A15 |
|---:|---:|---:|---:|
| 100,000 | ~156,250 rows/s | ~59,172 rows/s | ~36,496 rows/s |
| 1,000,000 | ~225,225 rows/s | ~82,508 rows/s | ~63,012 rows/s |
| 10,000,000 | ~231,160 rows/s | ~85,521 rows/s | ~64,902 rows/s |
| 20,000,000 | ~266,382 rows/s | ~85,455 rows/s | ~64,070 rows/s |

These values represent the complete pipeline from the client until completion of the COPY operation on the A15.

They should not be interpreted in isolation as the maximum capacity of the PostgreSQL server.

## Ubuntu Desktop → A15

Ubuntu Desktop achieved the highest throughput among the three clients used.

### 100 Thousand Rows
COPY                 = 100,000
real                 = 0.64 s
user                 = 0.20 s
sys                  = 0.05 s
cpu                  = 40%
max_rss_kb           = 4,152 KB
throughput           ≈ 156,250 rows/s
table size            = 14,983,168 bytes
WAL advancement       = 13,040,968 bytes

### 1 Million Rows
COPY                 = 1,000,000
real                 = 4.44 s
user                 = 1.73 s
sys                  = 0.35 s
cpu                  = 47%
max_rss_kb           = 4,060 KB
throughput           ≈ 225,225 rows/s
table size            = 149,233,664 bytes
WAL advancement       = 130,742,192 bytes

### 10 Million Rows

COPY                 = 10,000,000
real                 = 43.26 s
user                 = 17.17 s
sys                  = 3.62 s
cpu                  = 48%
max_rss_kb           = 4,120 KB
throughput           ≈ 231,160 rows/s
table size            = 1,490,173,952 bytes
WAL advancement       = 2,904,125,440 bytes

### 20 Million Rows

COPY                 = 20,000,000
real                 = 75.08 s
user                 = 34.07 s
sys                  = 7.05 s
cpu                  = 54%
max_rss_kb           = 4,064 KB
throughput           ≈ 266,382 rows/s
table size            = 2,980,044,800 bytes
WAL advancement       = 5,806,284,456 bytes

For the 20 million row run, pg_stat_database.tup_inserted advanced by exactly 20,000,000.

The activity observed in pg_stat_checkpointer during this run was:

num_requested   +11
num_done        +10
write_time      +139,900 ms
sync_time       +633 ms
buffers_written +7,717

## Motorola XT1941-3 → A15

The Motorola's local PostgreSQL instance was kept stopped during this series to prevent physical replication from automatically connecting to the A15.

The psql 18.6 client from the ARM64 environment itself was used.

### 100 Thousand Rows

COPY                 = 100,000
real                 = 1.69 s
user                 = 0.68 s
sys                  = 0.32 s
cpu                  = 59%
max_rss_kb           = 4,228 KB
throughput           ≈ 59,172 rows/s
table size            = 14,983,168 bytes

The observation interval for this run showed:

WAL advancement = 39,422,728 bytes

However, pg_stat_database.tup_inserted advanced by 300,000 during this interval, although the COPY operation inserted only 100,000 rows.

This indicates additional database activity between the snapshots used for this measurement.

For this reason, the WAL advancement value from this run should not be treated as a clean measurement associated solely with the 100 thousand row benchmark.

### 1 Million Rows

COPY                 = 1,000,000
real                 = 12.12 s
user                 = 6.32 s
sys                  = 2.82 s
cpu                  = 75%
max_rss_kb           = 4,228 KB
throughput           ≈ 82,508 rows/s
table size            = 149,233,664 bytes
WAL advancement       = 130,823,360 bytes
tup_inserted          = +1,000,000

### 10 Million Rows

COPY                 = 10,000,000
real                 = 116.93 s
user                 = 64.18 s
sys                  = 28.51 s
cpu                  = 79%
max_rss_kb           = 4,228 KB
throughput           ≈ 85,521 rows/s
table size            = 1,490,198,528 bytes
WAL advancement       = 2,826,203,760 bytes
tup_inserted          = +10,000,000

Observed checkpointer activity:

num_requested   +5
num_done        +5
write_time      +247,256 ms
sync_time       +373 ms
buffers_written +2,228

### 20 Million Rows

COPY                 = 20,000,000
real                 = 234.04 s
user                 = 128.05 s
sys                  = 56.81 s
cpu                  = 78%
max_rss_kb           = 4,228 KB
throughput           ≈ 85,455 rows/s
table size            = 3,066,126,336 bytes
WAL advancement       = 5,843,122,744 bytes
tup_inserted          = +20,000,000

Observed checkpointer activity:

num_timed       +2
num_requested   +11
num_done        +12
write_time      +564,656 ms
sync_time       +846 ms
buffers_written +2,137

For the 10 and 20 million row loads, throughput for the Motorola → A15 pipeline remained close to 85 thousand rows per second.

This result does not identify the limiting component in isolation. The pipeline involves awk generation, client CPU, psql, network, server processing, WAL, and storage.

## LG K11 Plus → A15

The LG K11 Plus was running Ubuntu 24.04 ARMHF in a chroot environment and used the 32-bit psql 18.6 client.

As with the Motorola, the local PostgreSQL instance was kept stopped during the tests.

### 100 Thousand Rows

COPY                 = 100,000
real                 = 2.74 s
user                 = 1.06 s
sys                  = 0.21 s
cpu                  = 46%
max_rss_kb           = 2,840 KB
throughput           ≈ 36,496 rows/s
table size            = 14,983,168 bytes
WAL advancement       = 13,115,048 bytes
tup_inserted          = +100,000

### 1 Million Rows

COPY                 = 1,000,000
real                 = 15.87 s
user                 = 9.28 s
sys                  = 1.84 s
cpu                  = 70%
max_rss_kb           = 2,840 KB
throughput           ≈ 63,012 rows/s
table size            = 149,233,664 bytes
WAL advancement       = 130,820,992 bytes
tup_inserted          = +1,000,000

### 10 Million Rows

COPY                 = 10,000,000
real                 = 154.08 s
user                 = 94.13 s
sys                  = 19.12 s
cpu                  = 73%
max_rss_kb           = 2,840 KB
throughput           ≈ 64,902 rows/s
table size            = 1,490,173,952 bytes
WAL advancement       = 2,903,298,504 bytes
tup_inserted          = +10,000,000

Observed checkpointer activity:

num_timed       +1
num_requested   +5
num_done        +5
write_time      +163,633 ms
sync_time       +286 ms
buffers_written +3,610

### 20 Million Rows

COPY                 = 20,000,000
real                 = 312.16 s
user                 = 190.06 s
sys                  = 37.33 s
cpu                  = 72%
max_rss_kb           = 2,840 KB
throughput           ≈ 64,070 rows/s
table size            = 3,066,068,992 bytes
WAL advancement       = 5,955,429,672 bytes
tup_inserted          = +20,000,000

Observed checkpointer activity:

num_requested   +11
num_done        +11
write_time      +436,912 ms
sync_time       +788 ms
buffers_written +12,768

## Client Comparison

The larger runs showed relatively stable behavior for both Android clients.

At 10 million rows:

Desktop      ≈ 231,160 rows/s
Motorola     ≈  85,521 rows/s
LG K11 Plus  ≈  64,902 rows/s

At 20 million rows:

Desktop      ≈ 266,382 rows/s
Motorola     ≈  85,455 rows/s
LG K11 Plus  ≈  64,070 rows/s

These numbers demonstrate differences in the end-to-end performance of the three pipelines tested.

In isolation, they do not establish whether the difference is caused primarily by CPU, data generation, network, ARM64/ARMHF architecture, the Android system, storage, or another component.

## Note About the origem Field

The content used in the origem field did not have exactly the same length on the three clients:

Desktop    = 7 characters
Motorola   = 8 characters
LGK11Plus  = 9 characters

This difference slightly changes the amount of data stored per row and should be taken into account when comparing physical table sizes between clients.

The next series uses Ubuntu Desktop as the client while keeping A15 → Motorola physical replication active during the loads.

# Benchmarks With Active Physical Replication

In this series, Ubuntu Desktop continued to be the client responsible for generating and transmitting the rows to the Samsung Galaxy A15.

The difference was the presence of the Motorola XT1941-3 as an active physical standby:

Ubuntu Desktop
      |
      | COPY FROM STDIN
      v
Samsung Galaxy A15
PostgreSQL 18.6
Primary
      |
      | Streaming Replication
      v
Motorola XT1941-3
PostgreSQL 18.6
Hot Standby

The replication used was asynchronous:

state      = streaming
sync_state = async

Therefore, commits on the primary did not wait for synchronous confirmation from the standby.

Before runs considered valid, the WAL positions of both the primary and standby were checked.

After the loads, the following were also checked:

- number of rows on the A15;
- ID range and uniqueness;
- WAL position advancement;
- `tup_inserted`;
- checkpointer activity;
- `pg_stat_replication` state;
- number of rows available on the Motorola;
- standby receive/replay positions;
- subsequent return of replication lag to zero.

## Consolidated Results

The official comparable results obtained with and without the active standby were:

| Rows | Without Replica | With Replica | Throughput Without Replica | Throughput With Replica |
|---:|---:|---:|---:|---:|
| 1,000,000 | 4.44 s | 5.80 s | ~225,225 rows/s | ~172,414 rows/s |
| 10,000,000 | 43.26 s | 62.78 s | ~231,160 rows/s | ~159,286 rows/s |
| 20,000,000 | 75.08 s | 128.29 s | ~266,382 rows/s | ~155,897 rows/s |

These differences are differences observed between end-to-end runs.

They do not represent an isolated measurement of the internal cost of replication.

## 1 Million Rows

The valid 1 million row run was performed with the Desktop using Ethernet and the Motorola connected to the A15 as a standby.

Client result:

COPY                 = 1,000,000
real                 = 5.80 s
user                 = 2.03 s
sys                  = 0.31 s
cpu                  = 40%
max_rss_kb           = 4,148 KB
throughput           ≈ 172,414 rows/s

The observed WAL position advancement was:

130,726,376 bytes

The table size was:

149,233,664 bytes

`pg_stat_database.tup_inserted` advanced by exactly:

+1,000,000

At the end of the verification, the replication positions were synchronized and the lag in bytes was zero.

The Motorola also showed:

1,000,000 rows
IDs from 1 through 1,000,000
1,000,000 distinct IDs

Comparing only the two observed runs:

without replica = 4.44 s
with replica    = 5.80 s

Time difference:

+1.36 s
approximately +30.6%

The calculated throughput reduction was approximately 23.5%.

These percentages describe only these runs and should not be generalized as fixed PostgreSQL replication overhead.

## First 10 Million Row Attempt: Discarded Run

Before configuring a larger WAL retention window, a 10 million row attempt was performed with the Motorola configured as a standby.

The client completed:

COPY                 = 10,000,000
real                 = 52.05 s
user                 = 19.94 s
sys                  = 3.40 s
cpu                  = 44%
max_rss_kb           = 4,048 KB
throughput           ≈ 192,123 rows/s

On the A15, the load itself was intact:

rows                  = 10,000,000
IDs                   = 1 through 10,000,000
distinct IDs          = 10,000,000
tup_inserted          = +10,000,000

However, when replication was checked after the load:

pg_stat_replication = 0 rows

On the Motorola:

pg_stat_wal_receiver = 0 rows
benchmark_copy        = 0 rows

The standby log repeatedly showed a message equivalent to:

requested WAL segment ... has already been removed

The standby had lost the continuity required to continue streaming.

This run was therefore discarded from the official active-replication performance comparison.

The 52.05-second result remains documented as part of the failure experiment, but it is not used as an official result for the series with intact replication.

### Condition That Allowed the Required WAL to Be Lost

At that time, the primary used:

wal_keep_size = 0

and there was no replication slot protecting the WAL required by the standby.

During intensive WAL generation, an interruption in standby continuity allowed older segments that it still needed to be recycled by the primary.

When the Motorola attempted to continue streaming, the requested segment was no longer available.

Recovery required a new physical copy using `pg_basebackup`.

## Introduction of wal_keep_size = 8GB

After the experimental failure, the A15 was configured with:

wal_keep_size = 8GB

The setting was applied through `ALTER SYSTEM`, and PostgreSQL was restarted.

The purpose of this setting in the experiment was to maintain a minimum window of old WAL large enough to allow the Motorola to recover from temporary lag during intensive loads.

This value was chosen for the experimental environment.

It should not be interpreted as a universal recommendation for other installations.

It is also important to distinguish:

wal_keep_size = 8GB
max_wal_size  = 1GB
min_wal_size  = 80MB

These settings serve different purposes.

`max_wal_size` participates in checkpoint-related control and does not act as a hard limit preventing `pg_wal` from growing beyond that size.

`wal_keep_size`, in turn, influences the minimum amount of old WAL retained to allow lagging standbys to recover.

## Second 10 Million Row Run: Valid

After rebuilding the Motorola and configuring `wal_keep_size = 8GB`, the 10 million row test was repeated.

Before the load:

- A15 and Motorola were streaming;
- the table was empty;
- the standby was synchronized;
- `wal_keep_size` was configured to 8GB.

Client result:

COPY                 = 10,000,000
real                 = 62.78 s
user                 = 21.29 s
sys                  = 3.46 s
cpu                  = 39%
max_rss_kb           = 4,096 KB
throughput           ≈ 159,286 rows/s

On the A15:

rows                  = 10,000,000
min_id                = 1
max_id                = 10,000,000
distinct_ids          = 10,000,000
tup_inserted          = +10,000,000
table size            = 1,490,182,144 bytes
WAL advancement       = 2,963,995,672 bytes

Observed checkpointer activity:

num_requested   +5
num_done        +4
write_time      +108,871 ms
sync_time       +128 ms
buffers_written +1,579

During the verification immediately after the load, the Motorola remained connected in the following state:

streaming / async

The standby was lagging and still receiving WAL.

Later, a query performed directly on the Motorola confirmed:

rows            = 10,000,000
min_id          = 1
max_id          = 10,000,000
distinct_ids    = 10,000,000

After catch-up, the A15 showed:

primary_lsn = B/E4AD7B40
sent_lsn    = B/E4AD7B40
write_lsn   = B/E4AD7B40
flush_lsn   = B/E4AD7B40
replay_lsn  = B/E4AD7B40

primary_replay_lag_bytes = 0
sent_replay_lag_bytes    = 0

The replica completely recovered from the lag without requiring another `pg_basebackup`.

### Comparison of the 10 Million Row Run

Without replication:

real       = 43.26 s
throughput ≈ 231,160 rows/s

With active and intact replication:

real       = 62.78 s
throughput ≈ 159,286 rows/s

Observed difference:

time       = +19.52 s
time (%)   ≈ +45.1%
throughput ≈ -31.1%

Again, these values describe the end-to-end pipeline of the two runs and do not isolate the cost of replication.

## 20 Million Row Run With Replication

The 20 million row run was performed while maintaining:

wal_keep_size = 8GB

Before the load, the Motorola showed:

rows        = 0
status      = streaming
receive_lsn = replay_lsn

Desktop result:

COPY                 = 20,000,000
real                 = 128.29 s
user                 = 43.44 s
sys                  = 7.46 s
cpu                  = 39%
max_rss_kb           = 3,976 KB
throughput           ≈ 155,897 rows/s

On the A15:

rows                  = 20,000,000
min_id                = 1
max_id                = 20,000,000
distinct_ids          = 20,000,000
tup_inserted          = +20,000,000
table size            = 2,980,126,720 bytes
WAL advancement       = 5,865,908,800 bytes

The observed advancement corresponds to approximately 5.46 GiB.

### Checkpointer Activity

During the 20 million row run, the following differences were observed:

num_timed       0
num_requested   +11
num_done        +10
write_time      +267,630 ms
sync_time       +574 ms
buffers_written +6,331

### Standby Lag During the 20 Million Row Run

In the snapshot taken after the load, the Motorola was still connected:

state      = streaming
sync_state = async

The observed positions were:

primary_lsn = D/4251D080
sent_lsn    = C/85052000
write_lsn   = C/84C32000
flush_lsn   = C/84C32000
replay_lsn  = C/84C30468

The calculated distance between the current primary position and the standby replay position at that moment was:

3,180,252,184 bytes

This corresponds to approximately 2.96 GiB of lag relative to the primary in that snapshot.

The difference between the WAL that had been sent and the WAL that had been replayed was:

4,332,440 bytes

Therefore, at that moment, a large part of the distance to the primary was still related to WAL transmission progress, rather than only to a large amount of already received WAL waiting for replay.

### Availability of the 20 Million Rows on the Standby

During the catch-up process, a query performed directly on the Motorola confirmed:

in_recovery    = true
status         = streaming
rows           = 20,000,000
min_id         = 1
max_id         = 20,000,000
distinct_ids   = 20,000,000

This demonstrates that the standby had already replayed the commit required to make the 20 million rows visible to queries, although it was still processing subsequent WAL.

Later, the A15 confirmed complete recovery:

primary_lsn = D/42526540
sent_lsn    = D/42526540
write_lsn   = D/42526540
flush_lsn   = D/42526540
replay_lsn  = D/42526540

primary_replay_lag_bytes = 0
sent_replay_lag_bytes    = 0

The Motorola therefore returned to zero lag without rebuilding the replica.

### Comparison of the 20 Million Row Run

Without replication:

real       = 75.08 s
throughput ≈ 266,382 rows/s

With active replication:

real       = 128.29 s
throughput ≈ 155,897 rows/s

Observed difference:

time       = +53.21 s
time (%)   ≈ +70.9%
throughput ≈ -41.5%

These differences should not be presented as fixed PostgreSQL replication overhead.

## Final WAL State

After completion of the benchmarks and full Motorola catch-up, the A15 showed:

wal_keep_size = 8GB
max_wal_size  = 1GB
min_wal_size  = 80MB

The directory:

/usr/local/pgsql18/data/pg_wal

occupied approximately:

8.6G

The A15 filesystem showed:

225G total
87G used
139G available
39% used

Replication ended in the following state:

state      = streaming
sync_state = async
lag        = 0 bytes

with the primary and standby at the same WAL position.

## Experimental WAL Retention Result

The tests produced two distinct situations in the same environment.

Before:

wal_keep_size = 0
standby lost continuity
required WAL was removed
replication could not continue
a new pg_basebackup was required

After:

wal_keep_size = 8GB
10 million row load completed
20 million row load completed
approximately 5.46 GiB of WAL advancement during the 20 million row load
standby reached approximately 2.96 GiB behind the primary
standby remained streaming
20 million rows became queryable on the standby
standby caught up
final lag = 0
no new pg_basebackup was required

This result demonstrates the behavior observed specifically in this experimental environment.

It does not establish that 8GB is the appropriate value for all systems.

The required retention depends, among other factors, on the WAL generation rate, the possible duration of standby interruptions, available space, and the replication strategy used.

# Experimental Conclusions

The benchmarks demonstrated that it was possible to execute remote loads of up to 20 million rows in a single `COPY FROM STDIN` operation into PostgreSQL 18.6 running on the Samsung Galaxy A15 inside Ubuntu 24.04 in a chroot environment.

In the runs performed, the A15 correctly received loads originating from three different types of clients:

- Ubuntu Desktop;
- Android ARM64;
- Android ARMHF/32-bit.

The largest test performed inserted 20 million rows in a single `COPY` operation.

Without replication, Ubuntu Desktop completed this load in:

75.08 seconds

With the Motorola operating as a physical standby, the comparable run was completed in:

128.29 seconds

In both cases, all 20 million rows were validated on the primary.

In the run with replication, the same 20 million rows were also subsequently validated on the standby.

## PostgreSQL on Android as a Server

The results demonstrate that, in the tested environment, PostgreSQL 18.6 compiled for ARM64 was able to operate on the Samsung Galaxy A15 as a database server and receive large-volume remote loads.

The benchmarks do not establish equivalence between a smartphone and conventional server hardware.

They demonstrate the functionality and performance observed on this specific hardware and configuration.

## Android Devices as Clients

The Motorola and LG K11 Plus were able to generate and transmit millions of rows directly to the A15 through `COPY FROM STDIN`.

For the larger loads, the observed throughput stabilized at approximately:

Motorola ARM64    ≈ 85 thousand rows/s
LG K11 Plus ARMHF ≈ 64 thousand rows/s

Ubuntu Desktop achieved significantly higher throughput with the same type of pipeline.

The benchmark did not isolate which component explains this difference.

## Physical Replication Between Android Devices

PostgreSQL 18.6 physical replication between the A15 and Motorola remained functional during the valid runs of:

1 million
10 million
20 million

After the loads, the standby was able to reach the same WAL position as the primary again.

During the 20 million row run, a temporary lag of approximately:

3,180,252,184 bytes

was observed between the current primary position and the position replayed by the standby.

Even so, the Motorola remained streaming, made all 20 million rows available for queries, and subsequently returned to zero lag.

## WAL Retention

The experiment also demonstrated a real loss-of-replication-continuity scenario.

With:

wal_keep_size = 0

and without a replication slot, a standby interruption during intensive WAL generation allowed segments that were still required to be removed.

Rebuilding the standby with `pg_basebackup` was necessary.

After configuring:

wal_keep_size = 8GB

the subsequent 10 and 20 million row runs allowed the Motorola to recover from lag without another rebuild.

During the 20 million row run, the WAL position advanced by approximately 5.46 GiB over the measured interval.

The result is specific to this experiment and does not define 8GB as a recommended setting for other environments.

## Asynchronous Replication

All replication benchmarks described in this document used:

sync_state = async

Consequently, commits on the A15 did not depend on synchronous confirmation from the Motorola.

For this reason, the time difference between benchmarks with and without the standby should not be interpreted as direct waiting time for replica replay.

The execution involves several components that were not individually isolated.

# Benchmark Limitations

This project attempts to preserve both the raw results and their limitations.

The main limitations include:

- the tests were not performed in a laboratory with a fully isolated network;
- the devices have different hardware and architectures;
- Desktop, Motorola, and LG have different CPU capabilities;
- the network paths are not necessarily equivalent;
- the measured time includes row generation on the client;
- the measured time includes TCP/IP transmission;
- the measured time includes `psql` processing;
- the measured time includes server processing;
- checkpoints may occur during the runs;
- other cluster activity may contribute to WAL advancement;
- the benchmark does not separately measure CPU, network, and storage;
- the `origem` field has different lengths across the three clients;
- multiple statistical repetitions of each combination were not performed;
- the results represent the observed runs rather than a statistical distribution of performance.

## CPU Reported by GNU time

The `cpu` field presented in the results belongs to the process/pipeline executed on the client.

It does not directly represent CPU utilization on the Samsung Galaxy A15.

For example:

cpu = 39%

in a run performed on Ubuntu Desktop describes the utilization observed for the process measured on the Desktop.

It does not mean that PostgreSQL on the A15 used 39% CPU.

## WAL Advancement

The values referred to as `WAL advancement` correspond to the difference between LSN positions observed during the benchmark interval.

Because WAL belongs to the PostgreSQL cluster, these values should not be interpreted as the amount of WAL produced exclusively by the rows in `benchmark_copy`.

## Performance Comparisons

The percentages presented between runs with and without replication are descriptive comparisons of the observed results.

For example, the difference between:

43.26 s without replica

and:

62.78 s with replica

does not demonstrate that physical replication universally adds 45.1% to the duration of a `COPY` operation.

Determining the isolated cost of replication would require additional, repeated, and controlled experiments with specific instrumentation to separate the different components of the pipeline.

# Reproducibility

The methodology was deliberately kept simple.

Rows were generated sequentially on the client and sent to PostgreSQL through a pipe, without an intermediate file.

The general structure used was:

awk → pipe → psql → TCP/IP → COPY FROM STDIN → PostgreSQL

The loads used were:

100,000
1,000,000
10,000,000
20,000,000

The table was emptied before each valid run.

The larger loads were subsequently verified through row count, minimum ID, maximum ID, and number of distinct IDs.

During replication tests, the following positions were also checked:

sent_lsn
write_lsn
flush_lsn
replay_lsn

The expected final state for a run considered fully caught up was:

state = streaming

and:

primary_lsn = sent_lsn = write_lsn = flush_lsn = replay_lsn

with:

replay lag = 0 bytes

# Scope of the Results

The numbers published in this document should be understood as reproducible experimental results within a specific architecture, rather than as official performance specifications for the devices used.

The primary objective is to document what was possible to execute with PostgreSQL 18.6 on real Android devices and provide concrete data so that other users can compare their own experiments.

Future improvements may include:

- multiple repetitions of each benchmark;
- mean, median, and standard deviation;
- simultaneous measurement of server CPU;
- server memory utilization;
- network throughput;
- network latency;
- storage I/O and latency;
- instantaneous WAL generation rate;
- time required for the standby to catch up;
- comparison with replication slots;
- comparison between different `wal_keep_size` values;
- read benchmarks on the hot standby;
- concurrent queries on the primary and standby.
