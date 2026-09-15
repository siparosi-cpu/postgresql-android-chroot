#!/bin/bash
set -e

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

