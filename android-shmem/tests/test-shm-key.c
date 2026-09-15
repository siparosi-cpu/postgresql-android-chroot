#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/ipc.h>
#include <sys/shm.h>

int main(void)
{
    key_t key = 0x12345;
    size_t size = 4096;

    printf("key=%d size=%zu\n", (int)key, size);

    int shmid = shmget(key, size, IPC_CREAT | 0600);
    if (shmid < 0) {
        perror("shmget");
        return 1;
    }

    printf("shmget OK: shmid=%d\n", shmid);

    char *p = shmat(shmid, NULL, 0);
    if (p == (void *)-1) {
        perror("shmat");
        return 1;
    }

    printf("shmat OK\n");

    strcpy(p, "android-shmem funcionando");
    printf("write/read: %s\n", p);

    if (shmdt(p) != 0) {
        perror("shmdt");
        return 1;
    }

    printf("shmdt OK\n");

    if (shmctl(shmid, IPC_RMID, NULL) != 0) {
        perror("shmctl IPC_RMID");
        return 1;
    }

    printf("IPC_RMID OK\n");

    return 0;
}
