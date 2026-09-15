# Camada de compatibilidade android-shmem para PostgreSQL no Android

[English](README.md)

## Visão geral

Este diretório documenta o trabalho de compatibilidade de memória compartilhada utilizado para executar PostgreSQL 18.6 dentro de ambientes Ubuntu 24.04 chroot hospedados por dispositivos Android com acesso root.

O trabalho é baseado no projeto upstream `android-shmem`, de pelya:

https://github.com/pelya/android-shmem

O commit upstream exato utilizado durante o experimento foi:

```text
3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

Ele também está registrado em:

```text
upstream-commit.txt
```

As modificações contidas neste diretório foram extraídas diretamente da árvore de código-fonte utilizada para compilar a biblioteca de compatibilidade funcional no ambiente LG K11 Plus ARMHF/32 bits testado.

---

## Por que uma camada de compatibilidade foi necessária

O Android utiliza o kernel Linux, mas um Ubuntu chroot hospedado pelo Android não necessariamente disponibiliza todas as funcionalidades tradicionais do GNU/Linux da maneira esperada por softwares como o PostgreSQL.

Durante os testes, um programa utilizando a API tradicional de memória compartilhada System V falhou na chamada:

```c
shmget(...)
```

com:

```text
shmget: Function not implemented
```

O projeto `android-shmem` fornece uma implementação de compatibilidade em userspace para operações de memória compartilhada System V.

A biblioteca de compatibilidade foi carregada através de `LD_PRELOAD`, por exemplo:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so ./test-shm-key
```

---

## Comportamento do upstream

O código-fonte upstream testado continha uma restrição em `shmget()` que rejeitava chaves diferentes de `IPC_PRIVATE`.

Conceitualmente, o código original executava:

```c
if (key != IPC_PRIVATE)
{
    errno = EINVAL;
    return -1;
}
```

Durante os experimentos de compatibilidade com PostgreSQL, essa restrição impedia o funcionamento da chave de memória compartilhada diferente de `IPC_PRIVATE` utilizada pelo teste.

---

## Modificação 1 — Chaves diferentes de `IPC_PRIVATE`

A primeira modificação remove a rejeição de chaves diferentes de `IPC_PRIVATE`.

O programa de teste utiliza intencionalmente:

```c
key_t key = 0x12345;
```

que corresponde em decimal a:

```text
74565
```

A modificação exata do código-fonte está preservada em:

```text
patches/android-shmem-postgresql.patch
```

Após a alteração, a biblioteca de compatibilidade conseguiu processar a chave diferente de `IPC_PRIVATE` utilizada no teste.

Este repositório documenta o comportamento observado no ambiente testado. Não afirmamos que remover essa restrição seja apropriado para todos os possíveis usos do `android-shmem`.

---

## Modificação 2 — `__shmctl64` no ambiente ARMHF testado

Um problema adicional de compatibilidade foi observado no LG K11 Plus executando Ubuntu 24.04 ARMHF/32 bits no chroot.

A inspeção do executável de teste mostrou referências incluindo:

```text
shmget@GLIBC_2.4
shmat@GLIBC_2.4
__shmctl64@GLIBC_2.34
shmdt@GLIBC_2.4
```

A biblioteca de compatibilidade upstream exportava `shmctl`, enquanto o executável ARMHF testado referenciava `__shmctl64`.

Foi adicionada a seguinte função de compatibilidade:

```c
int __shmctl64 (int shmid, int cmd, void *buf)
{
    return shmctl(shmid, cmd, (struct shmid_ds *)buf);
}
```

O símbolo também foi adicionado ao `exports.txt`:

```text
__shmctl64;
```

O sistema de compilação upstream já utiliza:

```text
-Wl,--version-script=exports.txt
```

portanto o símbolo adicionado passa a fazer parte da interface exportada quando a biblioteca modificada é compilada.

---

## Observação importante sobre ARMHF

A modificação envolvendo `__shmctl64` não deve ser interpretada como requisito universal para todo sistema ARM de 32 bits.

O que foi comprovado experimentalmente é mais específico:

- o LG K11 Plus utilizou um ambiente ARM de 32 bits
- o Ubuntu 24.04 do chroot utilizou arquitetura ARMHF
- o PostgreSQL 18.6 foi compilado como executável ARM de 32 bits
- o executável de teste referenciou `__shmctl64@GLIBC_2.34`
- a biblioteca modificada exportou `__shmctl64`
- o teste de memória compartilhada foi concluído com sucesso
- posteriormente a inicialização do PostgreSQL foi concluída com sucesso no ambiente testado

Outros dispositivos e combinações de libc/ABI devem ser testados independentemente.

---

## Biblioteca verificada

A biblioteca instalada no LG K11 Plus era:

```text
/usr/local/lib/libandroid-shmem.so
```

e foi identificada como:

```text
ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV)
```

A biblioteca compilada no diretório do código-fonte era:

```text
/usr/local/src/android-shmem/libandroid-shmem-armv7l.so
```

Os dois arquivos apresentaram o mesmo Build ID durante a verificação:

```text
1fd8d3957942d5dc29ad3996345e9c12e08afcfb
```

A biblioteca instalada exportava:

```text
shmget
shmat
shmdt
shmctl
__shmctl64
```

Isso confirmou que a biblioteca instalada continha o símbolo de compatibilidade utilizado durante o experimento bem-sucedido.

---

## Programa de teste

O código-fonte exato do teste extraído do ambiente funcional do LG está armazenado em:

```text
tests/test-shm-key.c
```

Ele executa a seguinte sequência:

```text
shmget
  ↓
shmat
  ↓
escrita/leitura
  ↓
shmdt
  ↓
shmctl(IPC_RMID)
```

O teste solicita intencionalmente uma chave diferente de `IPC_PRIVATE`.

Uma execução bem-sucedida apresentou saída equivalente a:

```text
key=74565 size=4096
shmget OK
shmat OK
write/read: android-shmem funcionando
shmdt OK
IPC_RMID OK
```

O identificador numérico de memória compartilhada retornado por `shmget()` pode variar entre execuções.

---

## Compilando a biblioteca modificada

Comece pelo projeto upstream:

```bash
git clone https://github.com/pelya/android-shmem.git
cd android-shmem
```

Faça checkout do commit upstream exato utilizado neste experimento:

```bash
git checkout 3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

Inicialize o submódulo necessário:

```bash
git submodule update --init
```

Aplique o patch deste repositório:

```bash
git apply /caminho/para/android-shmem-postgresql.patch
```

Confira as modificações:

```bash
git diff
```

Compile utilizando o Makefile upstream:

```bash
make
```

O Makefile upstream nomeia a biblioteca de acordo com a arquitetura retornada por `arch`.

No ambiente LG testado, o resultado foi:

```text
libandroid-shmem-armv7l.so
```

---

## Instalação utilizada no experimento

No ambiente testado, a biblioteca resultante foi instalada como:

```text
/usr/local/lib/libandroid-shmem.so
```

Por exemplo:

```bash
cp libandroid-shmem-armv7l.so /usr/local/lib/libandroid-shmem.so
chmod 755 /usr/local/lib/libandroid-shmem.so
```

Confira a arquitetura:

```bash
file /usr/local/lib/libandroid-shmem.so
```

E examine os símbolos relevantes exportados:

```bash
readelf -Ws /usr/local/lib/libandroid-shmem.so \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

---

## Compilando o teste

Uma compilação nativa simples dentro do Ubuntu chroot pode ser realizada com:

```bash
gcc tests/test-shm-key.c -o test-shm-key
```

Se estiver investigando o comportamento da ABI, examine o executável:

```bash
file test-shm-key
```

e:

```bash
readelf -Ws test-shm-key \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

---

## Executando o teste

Primeiro, a execução sem a biblioteca de compatibilidade é útil como referência:

```bash
./test-shm-key
```

No ambiente problemático, a falha relevante foi:

```text
shmget: Function not implemented
```

Depois execute com a biblioteca modificada:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so \
  ./test-shm-key
```

No ambiente LG testado, todas as operações foram concluídas com sucesso até:

```text
IPC_RMID OK
```

---

## PostgreSQL

O teste de memória compartilhada não era o objetivo final.

Após validar a camada de compatibilidade, o PostgreSQL 18.6 foi inicializado e executado dentro do Ubuntu 24.04 chroot.

A instalação PostgreSQL utilizada foi:

```text
/usr/local/pgsql18
```

O executável PostgreSQL testado no LG foi identificado como:

```text
ELF 32-bit LSB pie executable, ARM, EABI5
```

utilizando o interpretador:

```text
/lib/ld-linux-armhf.so.3
```

A compilação do PostgreSQL identificou-se como uma versão `armv7l-unknown-linux-gnueabihf` de 32 bits.

---

## Memória compartilhada dinâmica do PostgreSQL

A configuração PostgreSQL testada também utiliza:

```conf
dynamic_shared_memory_type = mmap
```

Essa configuração e a biblioteca de compatibilidade `android-shmem` tratam mecanismos diferentes.

O trabalho de compatibilidade documentado aqui está relacionado ao comportamento da API de memória compartilhada System V encontrado no ambiente Android/chroot.

A opção `dynamic_shared_memory_type = mmap` controla a implementação de memória compartilhada dinâmica do PostgreSQL.

As duas coisas não devem ser tratadas como configurações equivalentes.

---

## Conteúdo do patch

O patch atualmente modifica somente:

```text
exports.txt
shmem.c
```

Em relação ao commit upstream:

```text
3d5c2b79b42c9edc3228574276e0dd24423fbfa5
```

as estatísticas registradas do diff são:

```text
exports.txt   1 adição
shmem.c      11 adições, 6 remoções
```

O patch é intencionalmente pequeno para facilitar sua auditoria.

---

## Integridade

Os artefatos foram copiados diretamente do ambiente LG K11 Plus testado e posteriormente verificados no desktop de desenvolvimento.

Valores SHA-256:

```text
48a2c43ebab5f9f8e90dc27b32b0979f979ed52972f4f6767bed9e85de21f1ab  patches/android-shmem-postgresql.patch
929e4566df0451bddcfe690108fdd8aadce97553a37ffacd8716f0c22575087f  tests/test-shm-key.c
2bf1904453691462af11505d67f8cf1f7654391cc1b9d61b147881123e6dae22  upstream-commit.txt
```

Os hashes calculados no desktop de desenvolvimento foram idênticos aos calculados no ambiente LG antes da transferência.

---

## Licença upstream

Este trabalho é derivado do projeto `android-shmem`.

Os avisos de copyright, condições da licença e disclaimers do projeto upstream continuam aplicáveis ao código-fonte derivado.

O patch deste repositório é distribuído como uma modificação contra uma revisão upstream identificada, em vez de uma biblioteca binária substituta sem explicação.

Antes da redistribuição, consulte o arquivo `LICENSE` do projeto upstream.

---

## Estado experimental

Este trabalho de compatibilidade é experimental.

Ele foi validado nos dispositivos e ambientes documentados pelo projeto, mas kernels Android, comportamento da libc, arquiteturas de CPU, fabricantes e configurações de chroot podem variar significativamente.

A reprodução em outros hardwares é incentivada.

Ao informar resultados, é útil incluir:

- dispositivo/modelo Android
- versão do Android
- arquitetura da CPU
- saída de `uname -m`
- arquitetura do Ubuntu
- versão da glibc
- versão do PostgreSQL
- saída de `file` para o PostgreSQL
- saída de `file` para `libandroid-shmem.so`
- informações relevantes de símbolos obtidas com `readelf`
- resultado do programa de teste
