#!/system/bin/sh

ROOT=/data/local/ubuntu24

mountpoint -q "$ROOT/dev" || mount --bind /dev "$ROOT/dev"
mountpoint -q "$ROOT/dev/pts" || mount --bind /dev/pts "$ROOT/dev/pts"
mountpoint -q "$ROOT/proc" || mount -t proc proc "$ROOT/proc"
mountpoint -q "$ROOT/sys" || mount -t sysfs sysfs "$ROOT/sys"

export TMPDIR=/tmp
export TMP=/tmp
export TEMP=/tmp
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LANG=en_US.UTF-8

if chroot "$ROOT" /scripts/postgres/status.sh >/dev/null 2>&1; then
    echo "PostgreSQL ja esta em execucao."
else
    echo "Iniciando PostgreSQL..."
    chroot "$ROOT" /scripts/postgres/start.sh
fi

exec chroot "$ROOT" /bin/bash
