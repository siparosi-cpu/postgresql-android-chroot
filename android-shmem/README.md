# android-shmem Compatibility Layer for PostgreSQL on Android

[Português (Brasil)](README.pt-BR.md)

## Overview

This directory documents the shared-memory compatibility work used to run PostgreSQL 18.6 inside Ubuntu 24.04 chroot environments hosted by rooted Android devices.

The work is based on the upstream `android-shmem` project by pelya:

https://github.com/pelya/android-shmem

The exact upstream commit used during the experiment was:

```text
3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

It is also recorded in:

```text
upstream-commit.txt
```

The modifications contained here were extracted directly from the source tree used to build the working compatibility library on the tested LG K11 Plus ARMHF/32-bit environment.

---

## Why a Compatibility Layer Was Needed

Android uses the Linux kernel, but an Android-hosted Ubuntu chroot does not necessarily expose every traditional GNU/Linux facility in the way software such as PostgreSQL expects.

During testing, a program using the traditional System V shared-memory API failed at:

```c
shmget(...)
```

with:

```text
shmget: Function not implemented
```

The `android-shmem` project provides a userspace compatibility implementation for System V shared-memory operations.

The compatibility library was loaded using `LD_PRELOAD`, for example:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so ./test-shm-key
```

---

## Upstream Behavior

The tested upstream source contained a restriction in `shmget()` that rejected keys other than `IPC_PRIVATE`.

Conceptually, the original code performed:

```c
if (key != IPC_PRIVATE)
{
    errno = EINVAL;
    return -1;
}
```

During the PostgreSQL compatibility experiments, this restriction prevented the non-`IPC_PRIVATE` shared-memory key used by the test from succeeding.

---

## Modification 1 — Non-`IPC_PRIVATE` Keys

The first modification removes the rejection of keys different from `IPC_PRIVATE`.

The test program intentionally uses:

```c
key_t key = 0x12345;
```

which corresponds to decimal:

```text
74565
```

The exact source modification is preserved in:

```text
patches/android-shmem-postgresql.patch
```

After the modification, the compatibility library could process the tested non-`IPC_PRIVATE` key.

This repository documents the behavior observed in the tested environment. It does not claim that removing this restriction is appropriate for every possible use of `android-shmem`.

---

## Modification 2 — `__shmctl64` on the Tested ARMHF Environment

An additional compatibility issue was observed on the LG K11 Plus running an Ubuntu 24.04 ARMHF/32-bit chroot.

Inspection of the test executable showed references including:

```text
shmget@GLIBC_2.4
shmat@GLIBC_2.4
__shmctl64@GLIBC_2.34
shmdt@GLIBC_2.4
```

The upstream compatibility library exported `shmctl`, but the tested ARMHF executable referenced `__shmctl64`.

A compatibility wrapper was therefore added:

```c
int __shmctl64 (int shmid, int cmd, void *buf)
{
    return shmctl(shmid, cmd, (struct shmid_ds *)buf);
}
```

The symbol was also added to `exports.txt`:

```text
__shmctl64;
```

The upstream build already uses:

```text
-Wl,--version-script=exports.txt
```

so the added symbol becomes part of the exported interface when the modified library is built.

---

## Important ARMHF Qualification

The `__shmctl64` modification should not be interpreted as a universal requirement for every 32-bit ARM system.

What has been experimentally established is narrower:

- the LG K11 Plus used a 32-bit ARM environment
- Ubuntu 24.04 in the chroot used the ARMHF architecture
- PostgreSQL 18.6 was compiled as a 32-bit ARM executable
- the test executable referenced `__shmctl64@GLIBC_2.34`
- the modified compatibility library exported `__shmctl64`
- the shared-memory test completed successfully
- PostgreSQL initialization subsequently completed successfully in the tested environment

Additional devices and libc/ABI combinations should be tested independently.

---

## Verified Library

The installed library on the LG K11 Plus was:

```text
/usr/local/lib/libandroid-shmem.so
```

and was identified as:

```text
ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV)
```

The library built in the source directory was:

```text
/usr/local/src/android-shmem/libandroid-shmem-armv7l.so
```

Both files reported the same Build ID during verification:

```text
1fd8d3957942d5dc29ad3996345e9c12e08afcfb
```

The installed library exported:

```text
shmget
shmat
shmdt
shmctl
__shmctl64
```

This confirmed that the installed library contained the compatibility symbol used during the successful experiment.

---

## Test Program

The exact test source extracted from the working LG environment is stored at:

```text
tests/test-shm-key.c
```

It performs the following sequence:

```text
shmget
  ↓
shmat
  ↓
write/read
  ↓
shmdt
  ↓
shmctl(IPC_RMID)
```

The test intentionally requests a non-`IPC_PRIVATE` key.

A successful execution produced output equivalent to:

```text
key=74565 size=4096
shmget OK
shmat OK
write/read: android-shmem funcionando
shmdt OK
IPC_RMID OK
```

The exact numeric shared-memory identifier returned by `shmget()` may vary between executions.

---

## Building the Modified Library

Start from the upstream project:

```bash
git clone https://github.com/pelya/android-shmem.git
cd android-shmem
```

Check out the exact upstream commit used by this experiment:

```bash
git checkout 3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

Initialize the required submodule:

```bash
git submodule update --init
```

Apply the patch from this repository:

```bash
git apply /path/to/android-shmem-postgresql.patch
```

Review the modifications:

```bash
git diff
```

Then build using the upstream Makefile:

```bash
make
```

The upstream Makefile names the library according to the architecture reported by `arch`.

On the tested LG environment this produced:

```text
libandroid-shmem-armv7l.so
```

---

## Installing for the Experiment

For the tested environment, the resulting library was installed as:

```text
/usr/local/lib/libandroid-shmem.so
```

For example:

```bash
cp libandroid-shmem-armv7l.so /usr/local/lib/libandroid-shmem.so
chmod 755 /usr/local/lib/libandroid-shmem.so
```

Verify its architecture:

```bash
file /usr/local/lib/libandroid-shmem.so
```

And inspect the relevant exported symbols:

```bash
readelf -Ws /usr/local/lib/libandroid-shmem.so \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

---

## Compiling the Test

A simple native build inside the Ubuntu chroot can be performed with:

```bash
gcc tests/test-shm-key.c -o test-shm-key
```

Inspect the resulting executable if investigating ABI behavior:

```bash
file test-shm-key
```

and:

```bash
readelf -Ws test-shm-key \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

---

## Running the Test

First, running without the compatibility library is useful as a baseline:

```bash
./test-shm-key
```

In the problematic environment, the relevant failure was:

```text
shmget: Function not implemented
```

Then run with the modified library:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so \
  ./test-shm-key
```

The tested LG environment successfully completed all operations through:

```text
IPC_RMID OK
```

---

## PostgreSQL

The shared-memory test was not the final objective.

After validating the compatibility layer, PostgreSQL 18.6 was initialized and executed inside the Ubuntu 24.04 chroot.

The PostgreSQL installation used:

```text
/usr/local/pgsql18
```

The tested LG PostgreSQL executable was identified as:

```text
ELF 32-bit LSB pie executable, ARM, EABI5
```

using the interpreter:

```text
/lib/ld-linux-armhf.so.3
```

The PostgreSQL build identified itself as a 32-bit `armv7l-unknown-linux-gnueabihf` build.

---

## PostgreSQL Dynamic Shared Memory

The tested PostgreSQL configuration also uses:

```conf
dynamic_shared_memory_type = mmap
```

This setting and the `android-shmem` compatibility library address different mechanisms.

The compatibility work documented here concerns System V shared-memory API behavior encountered in the Android/chroot environment.

PostgreSQL's `dynamic_shared_memory_type = mmap` controls its dynamic shared-memory implementation.

They should not be treated as equivalent settings.

---

## Patch Contents

The patch currently modifies only:

```text
exports.txt
shmem.c
```

Relative to upstream commit:

```text
3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

the recorded diff statistics are:

```text
exports.txt   1 addition
shmem.c      11 additions, 6 deletions
```

The patch is intentionally small so that the modifications can be audited easily.

---

## Integrity

The artifacts were copied directly from the tested LG K11 Plus environment and then verified on the development desktop.

SHA-256 values:

```text
48a2c43ebab5f9f8e90dc27b32b0979f979ed52972f4f6767bed9e85de21f1ab  patches/android-shmem-postgresql.patch
929e4566df0451bddcfe690108fdd8aadce97553a37ffacd8716f0c22575087f  tests/test-shm-key.c
2bf1904453691462af11505d67f8cf1f7654391cc1b9d61b147881123e6dae22  upstream-commit.txt
```

The hashes calculated on the development desktop matched the hashes calculated on the LG environment before transfer.

---

## Upstream License

This work is derived from the `android-shmem` project.

The upstream project's copyright notices, license conditions, and disclaimers remain applicable to derived source code.

The patch in this repository is distributed as a modification against the identified upstream revision rather than as an unexplained precompiled replacement library.

Users should review the upstream `LICENSE` file before redistribution.

---

## Experimental Status

This compatibility work is experimental.

It has been validated on the devices and environments documented by this project, but Android kernels, libc behavior, CPU architectures, vendors, and chroot configurations vary significantly.

Reproduction on additional hardware is encouraged.

When reporting results, please include:

- Android device/model
- Android version
- CPU architecture
- output of `uname -m`
- Ubuntu architecture
- glibc version
- PostgreSQL version
- `file` output for PostgreSQL
- `file` output for `libandroid-shmem.so`
- relevant `readelf` symbol information
- test output
