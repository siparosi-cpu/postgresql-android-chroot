#!/system/bin/sh

ROOT=/data/local/ubuntu24

if [ -x "$ROOT/scripts/postgres/stop.sh" ]; then
    /system/bin/chroot "$ROOT" /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        /scripts/postgres/stop.sh
    '

    STOP_RESULT=$?

    if [ $STOP_RESULT -ne 0 ]; then
        echo "ERRO: PostgreSQL nao foi parado."
        echo "Ubuntu NAO sera desmontado."
        exit 1
    fi
else
    echo "ERRO: /scripts/postgres/stop.sh nao encontrado ou nao executavel."
    echo "Ubuntu NAO sera desmontado."
    exit 1
fi

echo "Aguardando PostgreSQL encerrar..."

i=0
while [ $i -lt 10 ]; do

    /system/bin/chroot "$ROOT" /bin/bash -c '
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        /scripts/postgres/status.sh
    ' >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        break
    fi

    sleep 1
    i=$((i + 1))
done

sleep 3

echo "Desmontando Ubuntu..."

umount "$ROOT/dev/pts" 2>/dev/null
umount "$ROOT/dev" 2>/dev/null
umount "$ROOT/proc" 2>/dev/null
umount "$ROOT/sys" 2>/dev/null
