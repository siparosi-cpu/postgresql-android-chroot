# PostgreSQL Streaming Replication between Android devices

[Português](README.pt-BR.md)

## Overview

This documentation describes the configuration and validation of PostgreSQL 18.6 physical streaming replication between two Android devices running Ubuntu 24.04 LTS in chroot environments.

The configuration was implemented and tested on physical devices used during the development of this project.

The currently demonstrated environment uses:

- Samsung Galaxy A15 — ARM64 — PostgreSQL primary
- Motorola Android One (deen) — ARM64 — PostgreSQL hot standby

Both devices run:

```text
PostgreSQL 18.6
Ubuntu 24.04 LTS
ARM64 / 64-bit
```

PostgreSQL was compiled from source code on both devices and uses the `android-shmem` compatibility library through `LD_PRELOAD`.

The installation follows the same layout on both devices:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

The PostgreSQL installation and compilation documentation is available at:

```text
../postgresql/
```

The Ubuntu chroot documentation is available at:

```text
../chroot/
```

The shared memory adaptation used by the project is documented at:

```text
../android-shmem/
```

The purpose of this section is to specifically document replication between the nodes, including primary configuration, standby creation, streaming validation, and the tests performed on the actual devices.

---

## Tested architecture

The topology used during the tests was:

```text
              local network 192.168.1.0/24

        Galaxy A15                    Motorola Android One
        192.168.1.50                  192.168.1.40

        PRIMARY                       HOT STANDBY
        PostgreSQL 18.6               PostgreSQL 18.6
        Ubuntu 24.04                  Ubuntu 24.04
        ARM64 / 64-bit                ARM64 / 64-bit

             |
             | physical WAL streaming
             | asynchronous
             |
             +------------------------------->

                        SELECT allowed
                        INSERT rejected
```

The Galaxy A15 keeps the database writable and generates the WAL records.

The Motorola continuously receives WAL through PostgreSQL's streaming replication protocol and remains in recovery as a hot standby.

During validation, the primary identified the Motorola through the address:

```text
192.168.1.40
```

and the standby identified the source server through:

```text
192.168.1.50:5432
```

---

## What this configuration represents

The configuration documented in this directory is an implementation of:

```text
PostgreSQL physical streaming replication

PRIMARY
   |
   | WAL
   v
HOT STANDBY
```

It allows changes made on the primary to be physically replicated to the standby.

During the tests, the following flow was demonstrated:

```text
INSERT on the Galaxy A15
        |
        v
WAL generation
        |
        v
streaming over the network
        |
        v
reception by the Motorola
        |
        v
WAL replay
        |
        v
SELECT available on the hot standby
```

The standby remains read-only while it is in recovery.

This configuration, by itself, should not be confused with a complete high-availability solution.

At the stage currently documented, the project does not automatically implement:

```text
failover
primary election
fencing
VIP
service discovery
automatic client redirection
automatic standby promotion
automatic reintegration of the former primary
```

These mechanisms may be investigated in later stages of the project.

This distinction is important because the purpose of this repository is to clearly separate what has already been implemented and demonstrated from what still belongs to future experimental work.

---

## Device environments

### Galaxy A15 — primary

During the data collection performed for this documentation, the Galaxy A15 reported:

```text
PostgreSQL 18.6
ARM64
64-bit
IP: 192.168.1.50
```

The function:

```sql
SELECT pg_is_in_recovery();
```

returned:

```text
f
```

confirming that the server was not in recovery and was operating as the primary.

The relevant settings reported by PostgreSQL itself were:

```text
wal_level             = replica
max_wal_senders       = 10
max_replication_slots = 10
hot_standby           = on
listen_addresses      = *
```

---

### Motorola Android One — hot standby

During the same validation, the Motorola reported:

```text
PostgreSQL 18.6
ARM64
64-bit
IP: 192.168.1.40
```

The function:

```sql
SELECT pg_is_in_recovery();
```

returned:

```text
t
```

confirming that the server was in recovery.

The file:

```text
/usr/local/pgsql18/data/standby.signal
```

was also present.

`pg_controldata` reported:

```text
Database cluster state: in archive recovery
```

These checks, combined with the active WAL receiver, confirmed the Motorola's role as a hot standby.

---

## Prerequisites

Before configuring replication, both devices must have functional and compatible PostgreSQL installations.

The tested environment used:

```text
Ubuntu 24.04 LTS
PostgreSQL 18.6
ARM64 / 64-bit
modified android-shmem
```

PostgreSQL must be operational independently on each device before replication is configured.

The devices must also be able to communicate over the network.

In the laboratory environment used by the project:

```text
PRIMARY
Galaxy A15
192.168.1.50

HOT STANDBY
Motorola Android One
192.168.1.40

PostgreSQL
TCP 5432
```

The addresses above correspond to the experimental environment and should be adapted to the network used by anyone reproducing the tests.

The authentication method used for the replication connection was:

```text
SCRAM-SHA-256
```
---

# Primary configuration — Galaxy A15

The Galaxy A15 was used as the PostgreSQL primary server.

In the tested environment:

```text
Device: Samsung Galaxy A15
IP: 192.168.1.50
PostgreSQL: 18.6
Architecture: ARM64 / 64-bit
Role: PRIMARY
```

Before replication was configured, PostgreSQL was already installed and running through the Ubuntu chroot.

The installation used is located at:

```text
/usr/local/pgsql18
```

and the data directory at:

```text
/usr/local/pgsql18/data
```

---

## postgresql.conf configuration

On the Galaxy A15, the settings relevant to replication were added to the file:

```text
/usr/local/pgsql18/data/postgresql.conf
```

The configuration used is:

```conf
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
```

During the preparation of this documentation, these settings were verified again directly in the configuration file:

```bash
grep -nE \
'^[[:space:]]*(listen_addresses|port|wal_level|max_wal_senders|max_replication_slots|hot_standby)[[:space:]]*=' \
/usr/local/pgsql18/data/postgresql.conf
```

The result observed on the Galaxy A15 was:

```text
893:listen_addresses = '*'
894:wal_level = replica
895:max_wal_senders = 10
896:max_replication_slots = 10
897:hot_standby = on
```

The settings were also verified through PostgreSQL itself:

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SHOW hot_standby;
SHOW listen_addresses;
```

The returned values were:

```text
wal_level             = replica
max_wal_senders       = 10
max_replication_slots = 10
hot_standby           = on
listen_addresses      = *
```

Therefore, the documentation does not rely solely on reading the configuration file: the values actually loaded by the server were also confirmed.

---

## Meaning of the main settings

The option:

```conf
wal_level = replica
```

causes the WAL to contain the information required to support physical replication.

The option:

```conf
max_wal_senders = 10
```

allows WAL sender processes responsible for sending WAL to standbys and other compatible replication connections.

In the experimental environment, the following setting was retained:

```conf
max_replication_slots = 10
```

Although this setting is enabled on the server, the mere presence of this value does not mean that a replication slot is being used by the standby documented here. The use of slots must be verified separately when necessary.

The setting:

```conf
listen_addresses = '*'
```

causes PostgreSQL to listen on the available network interfaces, allowing the Motorola to connect over the network.

Control over which clients can actually connect continues to be handled by `pg_hba.conf` and PostgreSQL's authentication mechanisms.

---

## Replication user

A dedicated PostgreSQL user was used for replication:

```text
replicador
```

This user has the attribute:

```text
REPLICATION
```

An equivalent role can be created on the primary using a command such as:

```sql
CREATE ROLE replicador
WITH REPLICATION
LOGIN
PASSWORD 'REPLACE_WITH_A_STRONG_PASSWORD';
```

The value above is only a placeholder.

**Do not use this literal password.**

The actual password used on the experimental devices is not stored in this repository.

To verify a role's attributes without exposing its password, you can use the following command in `psql`:

```text
\du replicador
```

or query only the required attributes through PostgreSQL views and system catalogs.

---

## pg_hba.conf configuration

Replication access from the Motorola was authorized on the Galaxy A15 through:

```text
/usr/local/pgsql18/data/pg_hba.conf
```

During the data collection performed for this documentation, the existing rule was:

```conf
host    replication    replicador    192.168.1.40/32    scram-sha-256
```

This rule has a specific meaning:

```text
host
  |
  +-- TCP/IP connection

replication
  |
  +-- connection intended for replication

replicador
  |
  +-- authorized PostgreSQL user

192.168.1.40/32
  |
  +-- only the Motorola address used in the test

scram-sha-256
  |
  +-- authentication method
```

Using `/32` restricts this rule specifically to the address:

```text
192.168.1.40
```

rather than allowing the replication user to connect from the entire local network.

The experimental environment also had a separate rule for normal PostgreSQL connections originating from the network:

```conf
host    all    all    192.168.1.0/24    scram-sha-256
```

This rule does not replace the replication-specific rule.

---

## Verifying the active pg_hba.conf rules

During the documentation process, the uncommented lines were verified with:

```bash
grep -vE '^[[:space:]]*(#|$)' \
  /usr/local/pgsql18/data/pg_hba.conf
```

On the Galaxy A15, the following was observed:

```text
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host    replication     replicador      192.168.1.40/32         scram-sha-256
host    all             all             192.168.1.0/24           scram-sha-256
```

These are the rules observed in the experimental environment and should not be copied indiscriminately to other installations.

In particular, local authentication policies should be evaluated according to the security requirements of the environment in which PostgreSQL will be running.

---

## Restarting or reloading the configuration

Changes to certain PostgreSQL settings may require the server to be restarted.

In this project, PostgreSQL is managed through the following scripts:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

To restart PostgreSQL using the project's standardized procedure:

```bash
/scripts/postgres/restart.sh
```

The scripts are preserved in the repository at:

```text
../scripts/postgres/
```

---

## Confirming that the Galaxy A15 is the primary

After startup, the following query was executed:

```sql
SELECT pg_is_in_recovery();
```

On the Galaxy A15, the observed result was:

```text
f
```

In other words:

```text
pg_is_in_recovery() = false
```

This confirms that the server was not running in recovery.

Conceptually:

```text
Galaxy A15
192.168.1.50

pg_is_in_recovery()
        |
        +-- false
              |
              v
           PRIMARY
```

---

## State of the primary without the standby connected

A useful behavior was recorded during the preparation of this documentation.

With PostgreSQL running on the Galaxy A15, but before PostgreSQL was started on the Motorola, the following query was executed:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

The result was:

```text
(0 rows)
```

This did not indicate a configuration failure.

At that moment, there was simply no standby connected to the primary's WAL sender.

Later, after the Motorola was started, the same query showed an active replication connection.

This difference was observed during the same validation procedure and will be shown in the following sections.

---

# Preparing the hot standby — Motorola

The Motorola Android One was used as the hot standby for the Galaxy A15.

In the tested environment:

```text
Device: Motorola Android One (deen)
IP: 192.168.1.40
PostgreSQL: 18.6
Architecture: ARM64 / 64-bit
Role: HOT STANDBY
```

As on the Galaxy A15, PostgreSQL was compiled and installed at:

```text
/usr/local/pgsql18
```

The data directory used by the PostgreSQL cluster is:

```text
/usr/local/pgsql18/data
```

Before converting an existing installation into a standby, any important data directory should be preserved.

**Never replace a `PGDATA` containing data that is still needed without having a verified backup.**

---

## Source of the standby data

Physical streaming replication does not initially create a complete copy of the database simply by connecting the standby to the primary.

The Motorola must start from a consistent copy of the Galaxy A15 cluster.

For this purpose, PostgreSQL provides:

```text
pg_basebackup
```

Conceptually:

```text
Galaxy A15
PRIMARY
192.168.1.50
     |
     | pg_basebackup
     |
     | initial physical copy
     v
Motorola
192.168.1.40
     |
     v
PGDATA
```

After this initial copy, subsequent changes can be received through WAL streaming.

---

## Stopping PostgreSQL before replacing PGDATA

PostgreSQL on the Motorola should not be using the data directory while it is being prepared to receive the base backup.

In the project, the server can be stopped using:

```bash
/scripts/postgres/stop.sh
```

and its status can be checked with:

```bash
/scripts/postgres/status.sh
```

Before removing or renaming any existing data directory, confirm that PostgreSQL has actually stopped.

---

## Preserving an existing PGDATA

If the Motorola already has a PostgreSQL cluster that needs to be preserved, one possible approach is to rename it before running `pg_basebackup`.

Example:

```bash
mv /usr/local/pgsql18/data \
   /usr/local/pgsql18/data.backup
```

The destination can then be created again:

```bash
mkdir /usr/local/pgsql18/data
chown postgres:postgres /usr/local/pgsql18/data
chmod 700 /usr/local/pgsql18/data
```

The name:

```text
data.backup
```

is only an example.

Before performing this procedure in an environment containing important information, confirm that sufficient storage space is available and that an independent backup exists.

---

## Running pg_basebackup

`pg_basebackup` must be executed on the device that will become the standby, connecting to the primary.

In this project's environment:

```text
Primary:     192.168.1.50
Port:        5432
User:        replicador
Destination: /usr/local/pgsql18/data
```

A reproducible way to perform the copy is:

```bash
setpriv \
  --reuid=postgres \
  --regid=postgres \
  --groups=1000,3003 \
  env LD_PRELOAD=/usr/local/lib/libandroid-shmem.so \
  /usr/local/pgsql18/bin/pg_basebackup \
  -h 192.168.1.50 \
  -p 5432 \
  -U replicador \
  -D /usr/local/pgsql18/data \
  -Fp \
  -Xs \
  -P \
  -R
```

The options used in this example serve the following purposes:

```text
-h 192.168.1.50
    primary

-p 5432
    PostgreSQL port

-U replicador
    dedicated replication user

-D /usr/local/pgsql18/data
    destination directory

-Fp
    plain format

-Xs
    WAL transferred by streaming during the backup

-P
    displays progress

-R
    prepares the destination to operate as a standby
```

The password for the `replicador` user, when requested, should be provided securely.

Do not place the actual password directly in public documentation, version-controlled scripts, or examples intended for GitHub.

---

## About the -R option

The option:

```text
-R
```

is especially important when preparing the standby.

It causes `pg_basebackup` to create the elements required for the resulting cluster to attempt to start as a standby.

Among them is:

```text
standby.signal
```

and connection information for the primary is added to the appropriate PostgreSQL configuration.

On the Motorola used in this project, the existence of the following file was later confirmed:

```text
/usr/local/pgsql18/data/standby.signal
```

During the data collection performed for this documentation:

```bash
ls -lh /usr/local/pgsql18/data/standby.signal
```

returned a file owned by:

```text
postgres:postgres
```

with a size of:

```text
0 bytes
```

The contents of the file are not important; its existence is used by PostgreSQL to determine standby behavior during startup.

---

## primary_conninfo and security

Preparing the standby may result in connection information for the primary being stored in:

```text
postgresql.auto.conf
```

This information may include:

```text
primary_conninfo
```

and this configuration may contain credentials.

For this reason:

**do not publish the actual `postgresql.auto.conf` file from a standby without first carefully reviewing its contents.**

An example intended for documentation should use only placeholder values:

```conf
primary_conninfo = 'host=192.168.1.50 port=5432 user=replicador password=REPLACE_WITH_THE_ACTUAL_PASSWORD'
```

The example above does not contain the password used in this project.

Never copy the actual laboratory credentials into the Git repository.

---

## Data directory permissions

After the base backup, the data directory must continue to be owned by the PostgreSQL user.

In the environment used:

```text
postgres:postgres
```

The `PGDATA` permissions are restricted:

```text
drwx------
```

They can be verified with:

```bash
ls -ld /usr/local/pgsql18/data
```

The user used by the project is:

```text
uid=1000(postgres)
gid=1000(postgres)
```

The particularities of this UID on Android are documented at:

```text
../postgresql/README.md
```

---

## Starting the standby

After preparing `PGDATA`, PostgreSQL can be started using the standardized script:

```bash
/scripts/postgres/start.sh
```

The script uses:

```text
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

and runs PostgreSQL with the user and group parameters used by the project.

The relevant structure is:

```bash
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

The actual scripts are preserved at:

```text
../scripts/postgres/
```

---

# Verifying the hot standby

After starting the Motorola, one of the first checks is:

```sql
SELECT pg_is_in_recovery();
```

During the data collection performed for this documentation, the result on the Motorola was:

```text
 pg_is_in_recovery
-------------------
 t
(1 row)
```

Therefore:

```text
pg_is_in_recovery() = true
```

This confirms that the cluster is running in recovery.

Conceptually:

```text
Motorola
192.168.1.40

standby.signal
      |
      v
PostgreSQL starts
      |
      v
recovery
      |
      v
pg_is_in_recovery() = true
      |
      v
HOT STANDBY
```

---

## Verification with pg_controldata

The following command was also used:

```bash
/usr/local/pgsql18/bin/pg_controldata \
  /usr/local/pgsql18/data
```

During data collection on the Motorola, the following was observed:

```text
Database system identifier: 7676117900798732860
Database cluster state: in archive recovery
```

The following values were also recorded:

```text
Latest checkpoint location:        1/F37F8E30
Latest checkpoint's REDO location: 1/F37F8DD8
Latest checkpoint's REDO WAL file: 0000000100000001000000F3
Latest checkpoint's TimeLineID:     1
Latest checkpoint's PrevTimeLineID: 1
```

These values correspond to the state observed at that specific moment and should not be treated as fixed values for a PostgreSQL installation.

LSNs, WAL files, XIDs, checkpoints, and other identifiers change as the database is used.

The purpose of preserving them here is to record evidence of the actual state observed during the experiment.

---

# Verifying the WAL receiver

On the Motorola, the following query was executed:

```sql
SELECT
    status,
    sender_host,
    sender_port,
    written_lsn,
    flushed_lsn,
    latest_end_lsn
FROM pg_stat_wal_receiver;
```

During validation, the result was:

```text
status         = streaming
sender_host    = 192.168.1.50
sender_port    = 5432
written_lsn    = 1/F37FE218
flushed_lsn    = 1/F37FE218
latest_end_lsn = 1/F37FE218
```

This query provides direct evidence from the standby side that a WAL receiver is connected to the Galaxy A15.

The observed relationship was:

```text
Motorola
192.168.1.40
HOT STANDBY
      |
      | pg_stat_wal_receiver
      |
      +-- status      = streaming
      +-- sender_host = 192.168.1.50
      +-- sender_port = 5432
                       |
                       v
                  Galaxy A15
                    PRIMARY
```

---

# Verifying replication from the primary

After the Motorola was started, the Galaxy A15 began showing an active connection in:

```text
pg_stat_replication
```

The query used was:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

During the data collection performed for this documentation, the result observed on the Galaxy A15 was:

```text
application_name = walreceiver
client_addr      = 192.168.1.40
state            = streaming
sync_state       = async
sent_lsn         = 1/F37FE218
write_lsn        = 1/F37FE218
flush_lsn        = 1/F37FE218
replay_lsn       = 1/F37FE218
```

This confirms, from the primary side, that the Motorola was connected and receiving WAL through streaming replication.

The same query had returned:

```text
(0 rows)
```

before the Motorola was started.

Therefore, during the same validation procedure, both states were observed:

```text
Motorola without PostgreSQL connected
        |
        v
pg_stat_replication
        |
        +-- 0 rows


Motorola started
        |
        v
WAL receiver connects to the A15
        |
        v
pg_stat_replication
        |
        +-- client_addr = 192.168.1.40
        +-- state       = streaming
        +-- sync_state  = async
```

---

## Asynchronous replication

On the Galaxy A15, the following was observed:

```text
sync_state = async
```

Therefore, the replication tested in this project was operating asynchronously.

Conceptually:

```text
Application
    |
    v
Galaxy A15
PRIMARY
    |
    +-- COMMIT on the primary
    |
    +-- WAL
          |
          | asynchronous streaming
          v
       Motorola
       HOT STANDBY
```

With asynchronous replication, a commit on the primary does not necessarily depend on confirmation that the standby has already persisted or replayed that WAL.

Consequently, the existence of streaming replication should not be interpreted as a guarantee of zero data loss in the event of every possible type of failure.

This distinction will be important in future failover and high-availability experiments.

---

# Comparison of the observed LSNs

During data collection, the Galaxy A15 reported:

```text
sent_lsn   = 1/F37FE218
write_lsn  = 1/F37FE218
flush_lsn  = 1/F37FE218
replay_lsn = 1/F37FE218
```

During the same period, the Motorola reported through `pg_stat_wal_receiver`:

```text
written_lsn    = 1/F37FE218
flushed_lsn    = 1/F37FE218
latest_end_lsn = 1/F37FE218
```

Therefore, at that specific moment of observation:

```text
Galaxy A15                         Motorola

sent_lsn      1/F37FE218  ------> latest_end_lsn 1/F37FE218
write_lsn     1/F37FE218           written_lsn    1/F37FE218
flush_lsn     1/F37FE218           flushed_lsn    1/F37FE218
replay_lsn    1/F37FE218
```

The matching values show that, at the time of the query, the standby had caught up to the WAL position reported by the primary.

This **does not mean that the LSNs will always remain equal**.

During periods of intensive writes, network delays, high load, or slower replay, these values may temporarily diverge.

Therefore, this result should be interpreted as a snapshot of the replication state at that particular moment, rather than as a permanent guarantee of zero replication lag.

---

## A checkpoint is not the same as the current streaming position

On the Motorola, `pg_controldata` reported:

```text
Latest checkpoint location: 1/F37F8E30
```

while `pg_stat_wal_receiver` reported:

```text
latest_end_lsn = 1/F37FE218
```

These values do not need to be equal.

The position of the latest checkpoint and the most recent position received through streaming represent different information about PostgreSQL's internal state.

Therefore, the difference between these values should not, by itself, be interpreted as replication lag.

To monitor replication, the appropriate PostgreSQL views and functions should be used, including:

```text
pg_stat_replication
pg_stat_wal_receiver
```

---

# Real replication test

After confirming the `streaming` state from both sides, a specific test was performed for this documentation.

The objective was to demonstrate the complete flow:

```text
write on the primary
        |
        v
WAL
        |
        v
streaming replication
        |
        v
replay on the standby
        |
        v
read on the standby
```

---

## Creating the table on the Galaxy A15

On the Galaxy A15 primary, the following table was created:

```sql
CREATE TABLE IF NOT EXISTS replication_documentation_test
(
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origem text NOT NULL,
    mensagem text NOT NULL,
    criado_em timestamptz NOT NULL DEFAULT now()
);
```

The following row was then inserted:

```sql
INSERT INTO replication_documentation_test
    (origem, mensagem)
VALUES
    ('Galaxy A15', 'Physical streaming replication test A15 -> Motorola');
```

The operation was executed on the primary.

---

## Querying the Motorola

After the insertion on the Galaxy A15, the following query was executed on the Motorola hot standby:

```sql
SELECT *
FROM replication_documentation_test
ORDER BY id DESC
LIMIT 5;
```

The Motorola returned:

```text
id       = 1
origem   = Galaxy A15
mensagem = Physical streaming replication test A15 -> Motorola
```

The row also contained the timestamp corresponding to the insertion performed during the test.

This demonstrated that both the table definition and the row inserted on the Galaxy A15 had reached the Motorola through physical replication.

Conceptually:

```text
Galaxy A15
PRIMARY
192.168.1.50
     |
     | CREATE TABLE
     | INSERT
     |
     v
    WAL
     |
     | physical streaming replication
     v
Motorola
HOT STANDBY
192.168.1.40
     |
     | SELECT
     v
row found
```

---

# Demonstrating read-only mode on the hot standby

The reverse test was also performed.

After confirming that the Motorola could query the replicated row, an attempt was made to execute the following directly on it:

```sql
INSERT INTO replication_documentation_test
    (origem, mensagem)
VALUES
    ('Motorola', 'This INSERT should fail on the hot standby');
```

PostgreSQL responded:

```text
ERROR: cannot execute INSERT in a read-only transaction
```

The following command was then executed:

```sql
SHOW transaction_read_only;
```

The result was:

```text
transaction_read_only
----------------------
on
```

The following was also verified again:

```sql
SELECT pg_is_in_recovery();
```

with the result:

```text
pg_is_in_recovery
------------------
t
```

Therefore, during the same test, the following behavior was demonstrated:

```text
Motorola HOT STANDBY

SELECT
   |
   +-- allowed

INSERT
   |
   +-- rejected
       "cannot execute INSERT
        in a read-only transaction"

transaction_read_only = on

pg_is_in_recovery() = true
```

This behavior is consistent with the device's role as a hot standby while in recovery.

---

# Evidence observed from both sides

The checks performed make it possible to observe the same replication session from both devices.

On the Galaxy A15:

```text
pg_is_in_recovery() = false

pg_stat_replication:

application_name = walreceiver
client_addr      = 192.168.1.40
state            = streaming
sync_state       = async
```

On the Motorola:

```text
pg_is_in_recovery() = true
transaction_read_only = on

pg_stat_wal_receiver:

status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

In addition:

```text
standby.signal = present

Database cluster state =
in archive recovery
```

The complete relationship observed was:

```text
                 Galaxy A15
                    PRIMARY
                 192.168.1.50
                       |
                       |
                WAL generation
                       |
                       |
              physical streaming
                 asynchronous
                       |
                       v
                   Motorola
                 HOT STANDBY
                 192.168.1.40
                       |
                WAL reception
                       |
                  WAL replay
                       |
                       v
                    SELECT
```

---

# Queries on the hot standby

An important consequence of this architecture is that the Motorola can execute queries while continuing to receive and replay WAL.

This creates opportunities for read distribution experiments.

A future architecture being investigated by the project is:

```text
                    applications
                        |
                        v
                   decision layer
                    /          \
                   /            \
                  v              v
          Galaxy A15          Motorola
            PRIMARY         HOT STANDBY
               |                 |
            SELECT             SELECT
            INSERT
            UPDATE
            DELETE
```

At the current stage, this automatic query distribution has not yet been implemented.

What has already been demonstrated is that the hot standby can respond to queries against replicated data.

The routing strategy, load detection, and read overflow mechanism remain subjects for future experimental work.

---

# Limitations of the current demonstration

The documented tests demonstrate functional physical streaming replication between the two Android devices.

By themselves, they do not demonstrate:

```text
automatic failover
zero RPO
a specific RTO
complete high availability
automatic primary election
split-brain protection
fencing
automatic load balancing
automatic reintegration
guaranteed performance under any workload
```

These mechanisms require additional experiments and components.

The documentation maintains this distinction so that results that have already been demonstrated are not confused with future objectives.

---

# Behavior when the standby is disconnected

During the preparation of this documentation, the primary was observed operating without any standby connected.

On the Galaxy A15, with PostgreSQL running and the Motorola still disconnected, the query:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state
FROM pg_stat_replication;
```

showed no replication connections:

```text
(0 rows)
```

The Galaxy A15 continued operating normally as the primary.

After PostgreSQL was started on the Motorola, the connection appeared in `pg_stat_replication`:

```text
application_name = walreceiver
client_addr      = 192.168.1.40
state            = streaming
sync_state       = async
```

This demonstrates that, in the tested environment, the primary does not depend on the permanent presence of the standby to remain operational.

This behavior is consistent with the asynchronous configuration used.

---

## Standby reconnection

When the Motorola is available and can reach the Galaxy A15, its WAL receiver connects to the primary.

The relationship observed during the tests was:

```text
Motorola unavailable
        |
        v
Galaxy A15 continues as PRIMARY
        |
        v
pg_stat_replication = 0 rows


Motorola starts PostgreSQL
        |
        v
standby.signal detected
        |
        v
recovery
        |
        v
WAL receiver connects to the primary
        |
        v
state = streaming
```

The exact behavior after longer periods of disconnection depends on the availability of the WAL segments required for the standby to catch up with the primary again.

For this reason, the reconnection observed in the current tests should not be interpreted as a guarantee of automatic recovery after every possible duration or type of interruption.

---

# WAL retention and recovery after interruptions

A standby needs access to the WAL records required to continue its recovery process.

If a standby remains disconnected long enough and the required WAL segments are no longer available on the primary, recovery may require intervention.

This aspect will be important in the project's upcoming experiments.

PostgreSQL strategies that may be investigated include:

```text
replication slots
wal_keep_size
WAL archive
restore_command
new pg_basebackup
```

The current configuration has:

```text
max_replication_slots = 10
```

but this value only allows replication slots to be created.

It does not demonstrate that the Motorola is currently using a slot.

Before documenting the use of replication slots in this project, their actual use must be configured and experimentally verified.

---

# Monitoring replication

The replication state can be monitored from both the primary and the standby.

## On the primary

The main view used during the tests was:

```text
pg_stat_replication
```

Example:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

It makes it possible to observe information such as:

```text
connected standby
standby address
connection state
synchronous or asynchronous mode
WAL position sent
WAL position written
WAL position flushed
WAL position replayed
```

In the tested environment:

```text
client_addr = 192.168.1.40
state       = streaming
sync_state  = async
```

---

## On the standby

On the Motorola, the following view was used:

```text
pg_stat_wal_receiver
```

Example:

```sql
SELECT
    status,
    sender_host,
    sender_port,
    written_lsn,
    flushed_lsn,
    latest_end_lsn
FROM pg_stat_wal_receiver;
```

During the test:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

Other useful checks include:

```sql
SELECT pg_is_in_recovery();

SHOW transaction_read_only;
```

On the Motorola, the following values were observed:

```text
pg_is_in_recovery() = true
transaction_read_only = on
```

---

# Measuring replication lag

The equality of the LSNs observed during a test should not be used as the only way to permanently assess replication health.

In future benchmarks, WAL positions may be compared and, when applicable, timing information available in PostgreSQL views may also be analyzed.

On the primary, for example, differences can be observed between:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

One possible conceptual situation is:

```text
sent_lsn
    |
    | WAL sent
    v
write_lsn
    |
    | WAL written on the standby
    v
flush_lsn
    |
    | WAL persisted
    v
replay_lsn
    |
    | WAL applied
    v
data available on the standby
```

The interpretation of these positions should take workload, network conditions, storage, and database activity into account.

---

# Replication and query distribution

One of the project's experimental objectives is to evaluate whether Android smartphones can operate as small distributed PostgreSQL nodes.

The existence of a functional hot standby makes it possible to investigate an architecture in which read queries can use more than one device.

The initial idea is to keep the Galaxy A15 as the primary while also using it for queries as long as processing capacity remains available.

Conceptually:

```text
                       clients
                           |
                           v
                     SELECT queries
                           |
                           v
                     Galaxy A15
                       PRIMARY
                           |
                 capacity available?
                    /             \
                  yes             no
                   |               |
                   v               v
             SELECT on A15     new SELECT
                                   |
                                   v
                               Motorola
                              HOT STANDBY
```

The motivation is not simply to send all read queries to the standby.

The primary also has processing capacity that can be utilized.

The future objective is to investigate when the read workload on the Galaxy A15 begins to produce enough contention to justify routing new queries to the Motorola.

---

## Relationship with ingestion workload

In the system that motivated these experiments, large volumes of data may be ingested during certain periods.

This makes it useful to study separately:

```text
write workload
read workload
concurrency between writes and reads
available capacity on the primary
additional capacity on the standby
```

One possible experimental strategy is:

```text
period of higher ingestion
        |
        v
Galaxy A15
PRIMARY
predominantly writes
        |
        +------------------+
                           |
                           v
                       Motorola
                      HOT STANDBY
                         queries


period of lower ingestion
        |
        v
Galaxy A15
PRIMARY
        |
        +-- SELECT
        |
        +-- residual writes

Motorola
HOT STANDBY
        |
        +-- additional SELECT capacity
```

This policy has not yet been implemented automatically.

It represents a research direction for future benchmarks.

---

# From primary + hot standby to an experimental cluster

The currently demonstrated configuration provides a foundation for broader experiments.

The current stage can be represented as:

```text
DEMONSTRATED STAGE

Galaxy A15
PRIMARY
     |
     | physical streaming replication
     | asynchronous
     v
Motorola
HOT STANDBY
```

One possible evolution is to add a layer responsible for deciding where queries should be executed:

```text
FUTURE EXPERIMENTAL STAGE

                    clients
                        |
                        v
                  query router
                   /       \
                  /         \
                 v           v
          Galaxy A15      Motorola
            PRIMARY      HOT STANDBY
              |              |
            reads           reads
            writes
```

After that, availability mechanisms may be investigated:

```text
                  monitoring
                      |
                      v
                  node state
                      |
          +-----------+-----------+
          |                       |
          v                       v
      PRIMARY                 HOT STANDBY
          |
          |
     failure detected
          |
          v
    failover decision
          |
          v
 controlled promotion
```

These diagrams represent experimental objectives, not functionality that has already been implemented.

---

# Why failover requires additional precautions

Promoting a standby is only one part of a high-availability architecture.

A more complete solution needs to answer questions such as:

```text
How can a primary failure be detected correctly?

Who decides whether to promote the standby?

How can two instances accepting writes be prevented?

How can split-brain be prevented?

How do clients discover the new primary?

What happens when the former primary returns?

How will the former primary be reintegrated?

How can it be prevented from accepting writes again with divergent data?

What is the acceptable RPO?

What is the acceptable RTO?
```

For this reason, the project does not consider the existence of streaming replication sufficient to claim complete high availability.

These questions will be addressed as separate experiments.

---

# Split-brain

One of the risks that must be considered in future failover experiments is known as:

```text
split-brain
```

Conceptually, a dangerous situation would be:

```text
          loss of communication
                 |
        +--------+--------+
        |                 |
        v                 v
     Node A              Node B
 believes it is        promoted to
   PRIMARY               PRIMARY
        |                 |
        v                 v
      writes             writes
```

If two nodes accept independent writes, their histories may diverge.

For this reason, any future implementation of automatic failover must consider coordination and isolation mechanisms before allowing automatic promotion.

---

# Fencing

In high-availability architectures, fencing mechanisms can be used to prevent a node considered outdated or invalid from continuing to operate as a writable server.

In the context of Android devices, this topic has some interesting particularities because the nodes are independent smartphones, each with its own:

```text
Android kernel
Wi-Fi
storage
battery
power management
suspend state
```

No fencing mechanism has been implemented in this project so far.

This topic will be investigated before any attempt to implement automatic failover.

---

# Future node monitoring

A future monitoring layer may observe information such as:

```text
device online/offline
PostgreSQL online/offline
primary/standby role
WAL receiver state
WAL sender state
replication lag
CPU
RAM
I/O
temperature
Wi-Fi
available storage space
power/battery
thermal throttling
```

In the Android environment, some of these metrics may be obtained through the Ubuntu chroot, while others may need to be queried directly through Android or `/sys`.

The experimental architecture may therefore combine PostgreSQL information with information from the physical device.

---

# Particular characteristics of a smartphone-based cluster

Using smartphones as PostgreSQL nodes presents important differences compared with conventional servers.

These include:

```text
Wi-Fi as the primary network
mobile flash storage
more aggressive thermal limits
Android power management
battery
suspend behavior
possible process termination by the system
differences between manufacturers' kernels
SELinux
root access
different ARM architectures
32-bit and 64-bit userspaces
```

These characteristics do not automatically make the devices unsuitable for experimentation.

They represent additional variables that need to be measured and documented.

---

# Different architectures and the role of the LG K11 Plus

The physical replication currently demonstrated by the project takes place between two ARM64/64-bit devices:

```text
Galaxy A15
ARM64 / 64-bit
PostgreSQL 18.6
PRIMARY

        |
        | physical streaming replication
        v

Motorola Android One
ARM64 / 64-bit
PostgreSQL 18.6
HOT STANDBY
```

The LG K11 Plus uses a different architecture:

```text
LG K11 Plus
ARMHF / 32-bit
PostgreSQL 18.6
```

PostgreSQL 18.6 was successfully compiled and executed on this device, but the LG is not part of the physical replication configuration used between the Galaxy A15 and the Motorola.

---

## Logical replication tested on the LG

Logical replication between the primary PostgreSQL server and the LG K11 Plus was also tested.

The experiment demonstrated that this approach introduced administrative dependencies on the primary that were not desirable for the architecture of this project.

During the experiments, while logical replication objects associated with the database used by the LG were present, certain administrative operations on the primary, including attempts to drop the database involved in the replication configuration, were blocked until the corresponding dependencies were handled.

For the objectives of this project, this behavior added operational complexity without providing sufficient benefit to justify using the LG as a replica.

Logical replication with the LG was therefore excluded from the planned architecture.

This decision is specific to the objectives and experiments of this project and does not imply that PostgreSQL logical replication is generally unsuitable.

---

# Current role of the LG K11 Plus

The LG remains useful as an independent PostgreSQL device and as an auxiliary processing node.

The planned architecture now clearly separates the roles:

```text
                   Galaxy A15
                     PRIMARY
                   ARM64 / 64-bit
                        |
                        |
              physical streaming
                  replication
                        |
                        v
                     Motorola
                   HOT STANDBY
                   ARM64 / 64-bit


                    LG K11 Plus
                   ARMHF / 32-bit
                        |
                        |
                 independent node
                        |
              auxiliary processing
```

The LG can perform auxiliary tasks that do not depend on being part of the replication configuration of the main cluster.

Possible experiments include:

```text
data processing
transformations
extractions
batch tasks
queries against independent local databases
temporary storage
intermediate processing
auxiliary workers
```

Whenever PostgreSQL is useful for a particular task, the PostgreSQL 18.6 installation already compiled on the LG can be used as an independent local database.

---

## Separation between replication and processing

With this decision, the experimental architecture is conceptually divided into two groups:

```text
REPLICATED POSTGRESQL NODES

Galaxy A15
PRIMARY
   |
   | WAL
   v
Motorola
HOT STANDBY


AUXILIARY NODE

LG K11 Plus
ARMHF / 32-bit
   |
   +-- processing
   +-- batch tasks
   +-- workers
   +-- local PostgreSQL database when needed
```

This separation avoids introducing replication dependencies with the LG on the primary solely to take advantage of its computing capacity.

The device can contribute to the system without having to maintain a replicated copy of the primary database.

---

## Current project decision

Based on the experiments performed, the architecture currently adopted is:

```text
Galaxy A15
    |
    +-- PostgreSQL PRIMARY
    +-- writes
    +-- reads
    |
    +-------- physical streaming replication --------+
                                                       |
                                                       v
                                                   Motorola
                                                 HOT STANDBY
                                                 additional reads


LG K11 Plus
    |
    +-- independent PostgreSQL, when needed
    +-- auxiliary processing
    +-- no participation in primary replication
```

Therefore, future replication and high-availability experiments will initially focus on the pair:

```text
Galaxy A15 <-> Motorola
```

The LG will be treated separately as an auxiliary processing node.

---

## Future ARMHF/32-bit physical replication test

The fact that the LG K11 Plus does not currently participate in physical replication does not conclude the replication experiments on 32-bit devices.

One future possibility is to use two devices with compatible environments:

```text
ARMHF / 32-bit device
PostgreSQL 18.6
PRIMARY

        |
        | physical streaming replication
        v

ARMHF / 32-bit device
PostgreSQL 18.6
HOT STANDBY
```

This experiment would make it possible to investigate PostgreSQL physical replication separately on Android smartphones using an ARMHF/32-bit userspace.

The LG K11 Plus could then participate in a new experimental environment if another compatible device is prepared.

Before this test, the requirements for physical compatibility between the clusters should be carefully verified, including:

```text
architecture
userspace
PostgreSQL version
data format
build configuration
libraries used
Android/chroot environment
```

Therefore, the current state of the project can be summarized as:

```text
DEMONSTRATED

ARM64 / 64-bit
Galaxy A15 PRIMARY
        |
        | physical streaming replication
        v
Motorola HOT STANDBY


TESTED AND EXCLUDED FROM THE CURRENT ARCHITECTURE

Galaxy A15
        |
        | logical replication
        v
LG K11 Plus ARMHF / 32-bit


POSSIBLE FUTURE EXPERIMENT

ARMHF / 32-bit
PRIMARY
        |
        | physical streaming replication
        v
ARMHF / 32-bit
HOT STANDBY
```

ARMHF/32-bit physical replication has not yet been tested in this project and therefore remains a subject for future investigation.

---

# Replication security

Replication uses an actual PostgreSQL connection between devices on the network and should therefore be treated with the same security considerations as any PostgreSQL server.

In the documented environment, the Galaxy A15 has a specific rule allowing replication connections from the Motorola:

```text
host replication replicador 192.168.1.40/32 scram-sha-256
```

This rule restricts the replication connection to the IP address used by the Motorola.

The remaining access rules should be defined according to the requirements of each environment.

---

## Credentials

The user used for replication has the following attribute:

```text
REPLICATION
```

No actual password used during the experiments should be stored in this repository.

Particular care should be taken with:

```text
postgresql.auto.conf
primary_conninfo
.pgpass
scripts
configuration files
command history
backups
```

A `postgresql.auto.conf` file created during the preparation of a standby may contain sensitive information.

Before publishing any file related to replication, review its contents.

---

# Currently demonstrated state

So far, the experiments have directly demonstrated:

```text
Galaxy A15
ARM64 / 64-bit
PostgreSQL 18.6
PRIMARY
192.168.1.50

        |
        | physical streaming replication
        | asynchronous
        v

Motorola Android One
ARM64 / 64-bit
PostgreSQL 18.6
HOT STANDBY
192.168.1.40
```

The following have been demonstrated:

* PostgreSQL 18.6 running on both devices;
* primary and standby using Ubuntu 24.04 chroot;
* `android-shmem` loaded through `LD_PRELOAD`;
* `wal_level = replica`;
* WAL receiver connection;
* `state = streaming`;
* `sync_state = async`;
* `pg_is_in_recovery() = false` on the primary;
* `pg_is_in_recovery() = true` on the standby;
* presence of `standby.signal`;
* `in archive recovery` state on the Motorola;
* WAL reception and replay;
* reading replicated data on the hot standby;
* an attempted `INSERT` rejected on the standby;
* `transaction_read_only = on` on the Motorola;
* continued operation of the primary while the standby is disconnected;
* standby reconnection observed during the tests.

A complete functional test was also performed:

```text
CREATE TABLE / INSERT
        |
        v
Galaxy A15
PRIMARY
        |
        | WAL
        v
physical streaming replication
        |
        v
Motorola
HOT STANDBY
        |
        v
SELECT of the replicated row
```

---

# What has not yet been demonstrated

The current configuration should not be confused with a complete high-availability solution.

The following have not yet been demonstrated in this project:

```text
automatic failover
fully documented end-to-end manual failover
failback
reintegration of the former primary
fencing
split-brain protection
determined RPO
determined RTO
replication slot for the Motorola
WAL archive for standby recovery
recovery after prolonged WAL loss
automatic query load balancing
automatic overload detection
automatic promotion
cluster manager
```

These items will be addressed separately as they are actually tested.

---

# Next tests for the ARM64 cluster

The Galaxy A15 and Motorola pair provides a foundation for further experiments.

The next planned tests include:

```text
1. measure replication lag during intensive writes

2. interrupt the Motorola's Wi-Fi connection and measure recovery

3. keep the standby disconnected for progressively longer periods

4. observe WAL retention and recovery

5. test replication slots

6. test wal_keep_size

7. evaluate WAL archiving

8. restart the Motorola during streaming

9. restart the Galaxy A15

10. measure behavior after Android suspend

11. run concurrent SELECT queries on the primary

12. run concurrent SELECT queries on the standby

13. perform intensive writes on the primary while the standby handles queries

14. measure CPU, RAM, and I/O on both devices

15. measure temperature and thermal throttling

16. measure behavior with large volumes of WAL

17. test controlled manual promotion of the Motorola

18. study reintegration of the former primary
```

Each result will be documented only after it has been reproduced in the actual environment.

---

# Future query routing

One of the most important research directions will be determining when to use the Motorola to offload queries from the Galaxy A15.

The intention is not simply to route all `SELECT` queries to the standby.

One possible strategy is to initially use the primary:

```text
                     SELECT
                        |
                        v
                   Galaxy A15
                     PRIMARY
                        |
                 acceptable load?
                  /           \
                yes           no
                 |             |
                 v             v
             execute         route
             on A15             |
                                v
                            Motorola
                           HOT STANDBY
```

To implement something similar responsibly, it will first be necessary to determine which metrics actually represent saturation in the smartphone environment.

Possible indicators include:

```text
CPU
load average
available RAM
I/O
average query execution time
number of concurrent queries
PostgreSQL connections
replication lag
temperature
thermal throttling
```

The routing decision should be based on benchmarks rather than solely on an arbitrary CPU utilization threshold.

---

# Auxiliary nodes outside replication

Not every device needs to participate in replication in order to contribute to the system.

The LG K11 Plus currently represents this model.

```text
                         REPLICATED CLUSTER

                    Galaxy A15
                      PRIMARY
                         |
                         | WAL
                         v
                     Motorola
                    HOT STANDBY


                     AUXILIARY
                     PROCESSING

                     LG K11 Plus
                    ARMHF / 32-bit
                         |
                         +-- workers
                         +-- processing
                         +-- batch tasks
                         +-- local PostgreSQL
                             when needed
```

This separation makes it possible to explore devices with different characteristics without requiring all of them to participate in the same replication mechanism.

---

# Experimental scalability

A future evolution may add other compatible devices.

For example:

```text
                         PRIMARY
                       Galaxy A15
                           |
              +------------+------------+
              |                         |
              v                         v
          STANDBY 1                 STANDBY 2
          Motorola                  future ARM64
              |                         |
              +-----------+-------------+
                          |
                          v
                    additional read
                       capacity
```

This scenario has not yet been tested.

Before increasing the number of standbys, it will be necessary to evaluate the additional cost on the primary, especially:

```text
WAL senders
Wi-Fi network
CPU
I/O
WAL retention
power consumption
temperature
```

---

# Objective of the experiment

The objective of this work is not to claim that smartphones can replace conventional servers.

The objective is to investigate, using real devices, how far a PostgreSQL infrastructure can be built on top of:

```text
Android
shared Linux kernel
root access
Ubuntu chroot
ARM
PostgreSQL compiled from source
adapted shared memory
local network
streaming replication
```

The project is interested in both successful results and the limitations encountered.

A reproducible failure or an approach that was tested and discarded also provides useful information for understanding the limits of the architecture.

---

# Conclusion

The experiments performed demonstrated functional physical streaming replication between two PostgreSQL 18.6 installations running on ARM64 Android smartphones through Ubuntu 24.04 chroot environments.

The Galaxy A15 operates as the primary, while the Motorola Android One operates as the hot standby.

During validation, the Galaxy A15 reported the Motorola as:

```text
state      = streaming
sync_state = async
```

and the Motorola reported:

```text
pg_is_in_recovery() = true
transaction_read_only = on
```

The Motorola WAL receiver confirmed a connection to:

```text
192.168.1.50:5432
```

and a real test demonstrated that a table and a row created on the Galaxy A15 became available for querying on the Motorola.

An attempt to write directly to the hot standby was correctly rejected by PostgreSQL.

Therefore, the current result goes beyond simply running PostgreSQL independently on Android:

```text
Android + Ubuntu chroot + PostgreSQL
                    |
                    v
          two ARM64 devices
                    |
                    v
      physical streaming replication
                    |
                    v
        PRIMARY + HOT STANDBY
```

This provides a concrete foundation for the next experiments involving concurrent workloads, read distribution, failure recovery, and the behavior of a PostgreSQL cluster built with Android devices.

The project will continue to clearly distinguish what has been demonstrated on real devices from what remains a hypothesis or a subject for future experimentation.
