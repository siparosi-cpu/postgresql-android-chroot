# PostgreSQL 18.6 no Android com Ubuntu 24.04 Chroot

[English](README.md)

## Visão geral

Esta documentação descreve a compilação, instalação e execução do PostgreSQL 18.6 em dispositivos Android com acesso root, utilizando Ubuntu 24.04 LTS em ambiente chroot.

Os procedimentos documentados aqui são baseados em dispositivos reais utilizados durante o desenvolvimento deste projeto.

O objetivo não é apenas apresentar uma sequência de comandos, mas registrar as particularidades encontradas ao executar PostgreSQL diretamente sobre o kernel Linux do Android utilizando um userspace GNU/Linux fornecido pelo Ubuntu.

Os dispositivos atualmente utilizados no projeto são:

- Samsung Galaxy A15 — ARM64 — servidor PostgreSQL principal
- Motorola Android One (deen) — ARM64 — hot standby PostgreSQL
- LG K11 Plus — ARMHF/32 bits — nó experimental

Nos três dispositivos foi utilizado o mesmo layout principal:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

A versão do PostgreSQL testada é:

```text
PostgreSQL 18.6
```

---

## Arquitetura do ambiente

O PostgreSQL não está sendo executado dentro de uma máquina virtual.

O Ubuntu utiliza `chroot` e compartilha o mesmo kernel Linux utilizado pelo Android.

Conceitualmente:

```text
Dispositivo Android
        |
        +-- Kernel Linux do Android
                |
                +-- Android userspace
                |
                +-- Ubuntu 24.04 chroot
                        |
                        +-- PostgreSQL 18.6
                        |
                        +-- android-shmem
```

O chroot fornece ao PostgreSQL o userspace GNU/Linux, bibliotecas, ferramentas de compilação e uma visão própria do sistema de arquivos.

Entretanto, o chroot não fornece:

- kernel separado
- máquina virtual
- isolamento completo de processos
- namespace de usuários independente
- ciclo de vida independente para os processos

Essa distinção é importante para compreender diversos comportamentos observados durante os testes.

---

## Ambientes testados

### Samsung Galaxy A15

Ambiente comprovado:

```text
Ubuntu:       Ubuntu 24.04.4 LTS
Arquitetura:  aarch64 / ARM64
PostgreSQL:   18.6
PostgreSQL:   ELF 64-bit ARM aarch64
Source:       /usr/local/src/postgresql-18.6
Instalação:   /usr/local/pgsql18
PGDATA:       /usr/local/pgsql18/data
android-shmem: ELF 64-bit ARM aarch64
```

O Galaxy A15 é utilizado atualmente como PostgreSQL primary.

Na rede utilizada durante os experimentos:

```text
Galaxy A15
192.168.1.50
PostgreSQL primary
```

### Motorola Android One (deen)

O Motorola é um dispositivo ARM64 executando o mesmo Ubuntu 24.04 e PostgreSQL 18.6.

Ele foi configurado como hot standby do Galaxy A15 utilizando streaming replication físico do PostgreSQL.

Durante os testes:

```text
Motorola Android One
192.168.1.40
PostgreSQL hot standby
```

A replicação:

```text
Galaxy A15                         Motorola
PRIMARY                            HOT STANDBY
192.168.1.50                       192.168.1.40

     WAL streaming
---------------------------------------->
```

foi validada com sucesso.

### LG K11 Plus

O LG representa um caso particularmente interessante porque o ambiente Android instalado utiliza userspace de 32 bits.

Resultados observados:

```text
Ubuntu:       Ubuntu 24.04.4 LTS
uname -m:     armv7l
LONG_BIT:     32
PostgreSQL:   18.6
PostgreSQL:   ELF 32-bit ARM EABI5
Source:       /usr/local/src/postgresql-18.6
Instalação:   /usr/local/pgsql18
PGDATA:       /usr/local/pgsql18/data
android-shmem: ELF 32-bit ARM EABI5
```

O PostgreSQL foi compilado e executado com sucesso nesse ambiente ARMHF/32 bits.

Esse dispositivo também revelou uma particularidade relacionada ao símbolo `__shmctl64`, documentada posteriormente.

---

## Código-fonte do PostgreSQL

O PostgreSQL utilizado nos testes foi compilado diretamente a partir do código-fonte.

A árvore utilizada nos dispositivos é:

```text
/usr/local/src/postgresql-18.6
```

No LG, por exemplo, também foi preservado o arquivo:

```text
/usr/local/src/postgresql-18.6.tar.gz
```

O prefixo de instalação escolhido foi padronizado entre os dispositivos:

```text
/usr/local/pgsql18
```

Isso mantém a instalação independente dos pacotes PostgreSQL eventualmente fornecidos pela distribuição Ubuntu.

---

## Configuração real utilizada na compilação

Em vez de reconstruir posteriormente as opções utilizadas, o projeto recuperou as informações diretamente do PostgreSQL efetivamente instalado e funcional através de:

```bash
/usr/local/pgsql18/bin/pg_config --configure
```

e do arquivo:

```text
/usr/local/src/postgresql-18.6/config.status
```

A configuração comprovadamente utilizada foi:

```bash
./configure \
  --prefix=/usr/local/pgsql18 \
  --with-openssl \
  --with-libxml \
  --with-libxslt \
  --with-icu
```

A mesma configuração foi confirmada tanto no Galaxy A15 ARM64 quanto no LG ARMHF/32 bits.

O compilador registrado pelo PostgreSQL é:

```text
gcc
```

---

## Dependências de compilação

No ambiente ARM64 utilizado no Galaxy A15 foram identificados, entre outros, os seguintes pacotes relacionados à compilação:

```text
build-essential
bison
flex
gcc
libicu-dev
libreadline-dev
libssl-dev
libxml2-dev
libxslt1-dev
make
pkg-config
zlib1g-dev
```

Uma instalação típica das dependências utilizadas pode ser feita com:

```bash
apt update

DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential \
  bison \
  flex \
  libicu-dev \
  libreadline-dev \
  libssl-dev \
  libxml2-dev \
  libxslt1-dev \
  pkg-config \
  zlib1g-dev
```

Dependências exatas podem variar conforme a versão do Ubuntu e as opções adicionais escolhidas na compilação.

---

## Compilação

Com as dependências instaladas e o código-fonte extraído:

```bash
cd /usr/local/src/postgresql-18.6
```

configure:

```bash
./configure \
  --prefix=/usr/local/pgsql18 \
  --with-openssl \
  --with-libxml \
  --with-libxslt \
  --with-icu
```

Compile:

```bash
make
```

E instale:

```bash
make install
```

A instalação resultante utilizada pelo projeto fica em:

```text
/usr/local/pgsql18
```

A versão pode ser confirmada com:

```bash
/usr/local/pgsql18/bin/postgres --version
```

Resultado esperado para esta documentação:

```text
postgres (PostgreSQL) 18.6
```

O `initdb` também foi verificado:

```bash
/usr/local/pgsql18/bin/initdb --version
```

Resultado observado:

```text
initdb (PostgreSQL) 18.6
```

---

## Usuário PostgreSQL

Nos ambientes documentados foi utilizado:

```text
uid=1000(postgres)
gid=1000(postgres)
groups=1000(postgres)
```

O diretório de dados pertence ao usuário PostgreSQL:

```text
postgres:postgres
```

e utiliza permissões restritas:

```text
drwx------
```

Exemplo:

```text
/usr/local/pgsql18/data
```

---

## Atenção ao UID 1000 no Android

O uso do UID 1000 produz um comportamento que pode inicialmente causar confusão.

O Android e o Ubuntu chroot compartilham o mesmo kernel e, consequentemente, a mesma tabela de processos.

Entretanto, ferramentas dentro do Ubuntu traduzem os números de UID utilizando o `/etc/passwd` do Ubuntu.

Se:

```text
UID 1000 = postgres
```

dentro do Ubuntu, processos Android que também possuam UID numérico `1000` podem aparecer em ferramentas como `ps` com o nome:

```text
postgres
```

mesmo que esses processos não tenham nenhuma relação com o servidor PostgreSQL.

Portanto, neste ambiente não é recomendável identificar os processos PostgreSQL simplesmente procurando todos os processos cujo usuário apresentado seja `postgres`.

Uma forma mais confiável é utilizar:

```text
/usr/local/pgsql18/data/postmaster.pid
```

O primeiro número desse arquivo corresponde ao PID do postmaster.

Por exemplo:

```bash
POSTMASTER_PID=$(head -1 /usr/local/pgsql18/data/postmaster.pid)

echo "$POSTMASTER_PID"
```

---

## Por que android-shmem é utilizado

Durante os testes, o PostgreSQL encontrou incompatibilidades relacionadas à memória compartilhada System V no ambiente Android/chroot.

Um dos sintomas observados durante a investigação foi:

```text
shmget: Function not implemented
```

Para fornecer a compatibilidade necessária, o projeto utiliza uma versão modificada do projeto `android-shmem` de pelya.

A documentação completa dessa modificação encontra-se em:

```text
../android-shmem/
```

A biblioteca utilizada pelo PostgreSQL é instalada como:

```text
/usr/local/lib/libandroid-shmem.so
```

---

## LD_PRELOAD

O PostgreSQL é iniciado utilizando:

```text
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

Isso permite que determinadas chamadas relacionadas à memória compartilhada sejam interceptadas pela biblioteca de compatibilidade.

O script utilizado pelo projeto segue esta estrutura:

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

Os scripts reais utilizados encontram-se em:

```text
../scripts/postgres/
```

---

## Verificando se android-shmem está realmente carregado

Não dependemos apenas da presença de `LD_PRELOAD` no script.

Durante os testes foi verificado o ambiente do processo postmaster realmente em execução.

Primeiro obtenha o PID:

```bash
POSTMASTER_PID=$(head -1 /usr/local/pgsql18/data/postmaster.pid)
```

Depois:

```bash
tr '\0' '\n' < /proc/$POSTMASTER_PID/environ \
  | grep -E '^(LD_PRELOAD|PATH|HOME)='
```

No Galaxy A15 foi observado:

```text
HOME=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

No LG K11 Plus foi igualmente observado:

```text
HOME=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

Portanto, nos dois ambientes verificados, o processo PostgreSQL efetivamente herdou a biblioteca através de `LD_PRELOAD`.

---

## Grupos adicionais utilizados por setpriv

Embora:

```bash
id postgres
```

mostre normalmente:

```text
uid=1000(postgres) gid=1000(postgres) groups=1000(postgres)
```

os scripts do projeto iniciam PostgreSQL com:

```text
--groups=1000,3003
```

O grupo suplementar `3003` é atribuído ao processo pelo `setpriv` durante a inicialização.

Ele não precisa aparecer como grupo permanente do usuário `postgres` no `/etc/group` para que o processo iniciado dessa forma receba o grupo suplementar.

Esse detalhe é específico do ambiente Android utilizado neste projeto e deve ser considerado ao adaptar os scripts para outros dispositivos.

---

## dynamic_shared_memory_type

A configuração utilizada no ambiente Android inclui:

```conf
dynamic_shared_memory_type = mmap
```

Durante a investigação existiam duas ocorrências no arquivo de configuração em um dos ambientes:

```text
dynamic_shared_memory_type = posix
dynamic_shared_memory_type = mmap
```

A configuração efetiva utilizada foi ajustada para:

```conf
dynamic_shared_memory_type = mmap
```

Essa configuração diz respeito à memória compartilhada dinâmica do PostgreSQL e é distinta da compatibilidade System V fornecida através de `android-shmem`.

---

# Particularidade do LG K11 Plus: __shmctl64

O LG K11 Plus utiliza Ubuntu ARMHF/32 bits.

O executável PostgreSQL foi confirmado como:

```text
ELF 32-bit LSB pie executable, ARM, EABI5
```

Durante a investigação foi descoberto que o executável PostgreSQL possui referência ao símbolo:

```text
__shmctl64@GLIBC_2.34
```

A verificação foi feita com:

```bash
readelf -Ws /usr/local/pgsql18/bin/postgres \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

Entre os resultados observados:

```text
UND shmat@GLIBC_2.4
UND __shmctl64@GLIBC_2.34
UND shmdt@GLIBC_2.4
UND shmget@GLIBC_2.4
```

A implementação original utilizada como base fornecia `shmctl`, mas a adaptação ARMHF precisava também disponibilizar `__shmctl64`.

Foi acrescentado ao `shmem.c`:

```c
int __shmctl64 (int shmid, int cmd, void *buf)
{
    return shmctl(shmid, cmd, (struct shmid_ds *)buf);
}
```

E `exports.txt` passou a exportar:

```text
__shmctl64;
```

Depois da recompilação, a biblioteca utilizada no LG apresentou:

```text
shmget
shmat
shmdt
shmctl
__shmctl64
```

A verificação:

```bash
readelf -Ws /usr/local/lib/libandroid-shmem.so \
  | grep -E 'shm(get|at|dt|ctl)|__shmctl'
```

confirmou que `__shmctl64` estava presente na biblioteca.

Essa alteração está preservada no patch reproduzível:

```text
../android-shmem/patches/android-shmem-postgresql.patch
```

---

## Outra modificação importante no android-shmem

O código upstream utilizado como base restringia `shmget()` a:

```c
key == IPC_PRIVATE
```

A lógica original relevante era:

```c
if (key != IPC_PRIVATE)
{
    DBG ("%s: key %d != IPC_PRIVATE,  this is not supported", __PRETTY_FUNCTION__, key);
    errno = EINVAL;
    return -1;
}
```

Durante os testes essa restrição foi desativada.

No patch preservamos propositalmente o código original comentado:

```c
//if (key != IPC_PRIVATE)
//{
//    DBG ("%s: key %d != IPC_PRIVATE,  this is not supported", __PRETTY_FUNCTION__, key);
//    errno = EINVAL;
//    return -1;
//}
```

Além de reproduzir exatamente a alteração experimental utilizada, manter o trecho original visível torna mais fácil compreender qual comportamento upstream foi modificado.

Consulte `../android-shmem/` para a explicação completa.

---

# Scripts de gerenciamento

O projeto utiliza scripts padronizados nos dispositivos.

Dentro do Ubuntu:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

No Android:

```text
/data/local/start-ubuntu.sh
/data/local/stop-ubuntu.sh
```

As versões preservadas no repositório encontram-se em:

```text
../scripts/android/
../scripts/postgres/
```

A estrutura e os nomes foram mantidos iguais nos dispositivos testados para facilitar manutenção e reprodução.

---

## Inicialização

O fluxo normal é:

```text
Android root
     |
     +-- /data/local/start-ubuntu.sh
               |
               +-- monta /dev
               +-- monta /dev/pts
               +-- monta /proc
               +-- monta /sys
               |
               +-- verifica PostgreSQL
               |
               +-- inicia PostgreSQL se necessário
               |
               +-- abre Bash no Ubuntu chroot
```

O PostgreSQL é iniciado através de:

```text
/scripts/postgres/start.sh
```

---

## Encerramento normal

O procedimento normal de encerramento utiliza:

```text
/data/local/stop-ubuntu.sh
```

O script:

1. solicita o encerramento do PostgreSQL;
2. verifica se o PostgreSQL realmente encerrou;
3. somente então desmonta os recursos auxiliares do chroot.

Conceitualmente:

```text
stop-ubuntu.sh
       |
       +-- PostgreSQL stop
       |
       +-- aguarda encerramento
       |
       +-- confirma servidor parado
       |
       +-- umount /dev/pts
       +-- umount /dev
       +-- umount /proc
       +-- umount /sys
```

Esse continua sendo o procedimento recomendado pelo projeto.

---

# Ciclo de vida do PostgreSQL e comportamento do chroot

Durante os experimentos foi observado um comportamento importante.

Depois que PostgreSQL é iniciado através do Ubuntu chroot, sair do Bash com:

```bash
exit
```

não encerra o PostgreSQL.

Isso ocorre porque terminar o shell interativo não significa terminar os demais processos que foram iniciados através daquele ambiente.

O PostgreSQL continua existindo como processo no kernel Linux compartilhado com Android.

---

## Experimento de desmontagem com PostgreSQL em execução

Foi realizado também um teste manual separado do procedimento normal de desligamento.

Nesse experimento:

1. PostgreSQL foi iniciado através do chroot;
2. o shell Ubuntu foi encerrado;
3. PostgreSQL **não** foi parado;
4. as montagens auxiliares do chroot foram desmontadas manualmente;
5. o banco foi acessado remotamente a partir de um Ubuntu Desktop.

As montagens auxiliares desmontadas foram:

```text
/dev/pts
/dev
/proc
/sys
```

Mesmo após essa desmontagem, os processos PostgreSQL permaneceram ativos e o servidor continuou respondendo às conexões remotas durante o teste.

Conceitualmente:

```text
PostgreSQL iniciado
       |
       +-- sair do Bash
       |
       +-- desmontar /dev/pts
       +-- desmontar /dev
       +-- desmontar /proc
       +-- desmontar /sys
       |
       +-- processos PostgreSQL continuam
       |
       +-- conexão remota continua funcionando
```

Isso é possível porque:

```text
/data/local/ubuntu24
```

não é desmontado por essas operações.

Os arquivos principais continuam no armazenamento Android:

```text
/data/local/ubuntu24/usr/local/pgsql18
/data/local/ubuntu24/usr/local/pgsql18/data
/data/local/ubuntu24/usr/local/lib/libandroid-shmem.so
```

O teste demonstra uma diferença importante entre chroot e virtualização.

**Este resultado é uma observação experimental e não uma recomendação operacional.**

O procedimento normal continua sendo encerrar corretamente PostgreSQL antes de desmontar os recursos auxiliares.

---

# Acesso pela rede

O PostgreSQL foi configurado para aceitar conexões através da rede local.

Durante os testes no Galaxy A15 foi confirmado:

```sql
SHOW listen_addresses;
```

Resultado:

```text
*
```

A configuração de autenticação deve ser feita cuidadosamente em:

```text
/usr/local/pgsql18/data/pg_hba.conf
```

Não publique senhas reais, hashes de senha ou configurações contendo credenciais neste repositório.

---

# Streaming replication

A replicação física PostgreSQL foi configurada entre:

```text
Galaxy A15                         Motorola Android One

192.168.1.50                       192.168.1.40

PRIMARY                            HOT STANDBY
PostgreSQL 18.6                    PostgreSQL 18.6
ARM64                              ARM64

              WAL
---------------------------------------->
```

No primary foram confirmadas configurações compatíveis com replicação:

```text
wal_level = replica
max_wal_senders = 10
listen_addresses = *
```

Também foi criado um usuário dedicado com atributo:

```text
Replication
```

Credenciais reais não são incluídas no repositório.

---

## Criação do standby

O standby foi criado utilizando `pg_basebackup`.

O fluxo utilizado foi:

```text
PRIMARY
192.168.1.50
      |
      | pg_basebackup
      |
      v
HOT STANDBY
192.168.1.40
```

Após o `pg_basebackup`, foi criado:

```text
standby.signal
```

e a configuração de conexão com o primary foi gravada pelo PostgreSQL.

**Nunca publique `postgresql.auto.conf` real quando ele contiver senha de replicação.**

Utilize sempre valores fictícios em exemplos.

---

## Replicação confirmada

No primary, `pg_stat_replication` mostrou o Motorola em:

```text
state      = streaming
sync_state = async
```

Durante a validação, os seguintes LSNs chegaram ao mesmo valor:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

No standby:

```sql
SELECT pg_is_in_recovery();
```

retornou:

```text
t
```

E:

```sql
SELECT status, sender_host, sender_port
FROM pg_stat_wal_receiver;
```

confirmou:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

---

## Teste real de replicação

Uma linha foi inserida no Galaxy A15 primary:

```text
gravado no A15 e replicado para o Motorola
```

e posteriormente consultada com sucesso no Motorola standby.

Isso confirmou o fluxo completo:

```text
INSERT no A15
     |
     +-- WAL
           |
           +-- streaming
                  |
                  +-- replay no Motorola
                           |
                           +-- SELECT no standby
```

---

# Estratégia experimental de consultas

O projeto investiga uma estratégia em que o Galaxy A15 continua sendo o nó principal também para grande parte das consultas.

A motivação é prática: muitos Diários Oficiais são disponibilizados durante a noite ou madrugada, período em que a carga de usuários tende a ser menor.

Assim, o A15 pode realizar principalmente as gravações nesse período e permanecer disponível para grande quantidade de consultas durante o dia.

O Motorola não precisa receber todas as consultas simplesmente por ser uma réplica.

A estratégia investigada é:

```text
Consulta
   |
   v
Galaxy A15
PRIMARY
   |
   +-- capacidade disponível --> SELECT no A15
   |
   +-- gargalo de SELECT
             |
             +-- nova consulta
                     |
                     v
               Motorola
               HOT STANDBY
```

O objetivo futuro é utilizar a réplica como capacidade adicional quando houver concorrência ou gargalo de leitura no primary.

Essa política de distribuição ainda é experimental e será objeto de benchmarks específicos.

---

# Testes de inserção

Durante os experimentos também foram realizadas inserções em massa.

Em um teste remoto, o Motorola conectou-se ao PostgreSQL do A15 e executou uma inserção de 100.000 registros em uma única transação.

Foi observado aproximadamente:

```text
INSERT 100000: 920,761 ms
COMMIT:          29,499 ms
```

Esse resultado pertence ao ambiente experimental utilizado naquele momento e não deve ser interpretado como benchmark universal.

Outros testes utilizaram milhões de registros e `COPY`.

Os resultados detalhados serão organizados em:

```text
../benchmarks/
```

---

# Segurança

Este projeto documenta sistemas reais, mas o repositório público não deve conter credenciais reais.

Nunca publique:

```text
senhas PostgreSQL
senha do usuário de replicação
primary_conninfo contendo password
postgresql.auto.conf real com credenciais
chaves privadas
tokens
credenciais Android
dados pessoais
backups de bancos de produção
```

Antes de adicionar arquivos ao Git, procure informações sensíveis.

Por exemplo:

```bash
grep -RniE \
'password|passwd|senha|secret|token|private.key|BEGIN.*PRIVATE|primary_conninfo' \
. \
--exclude-dir=.git
```

Revise manualmente qualquer resultado antes do commit.

---

# O que foi comprovado até o momento

Os experimentos demonstraram:

- PostgreSQL 18.6 compilado a partir do código-fonte em Ubuntu 24.04 chroot
- execução em Android ARM64
- execução em Android ARMHF/32 bits
- PostgreSQL ELF 64-bit no Galaxy A15
- PostgreSQL ELF 32-bit no LG K11 Plus
- uso efetivo de `LD_PRELOAD`
- carregamento de `libandroid-shmem.so`
- adaptação de `shmget()` para chaves diferentes de `IPC_PRIVATE`
- compatibilidade `__shmctl64` no ambiente ARMHF/32 bits
- inicialização e encerramento através de scripts padronizados
- acesso PostgreSQL pela rede local
- inserções remotas
- ingestão de grandes volumes
- uso de `COPY`
- streaming replication físico ARM64 → ARM64
- hot standby em dispositivo Android
- consultas na réplica
- persistência do processo PostgreSQL após saída do shell chroot
- persistência observada após desmontagem manual das montagens auxiliares do chroot

---

# O que ainda precisa ser investigado

Entre os próximos testes estão:

- benchmarks formais de SELECT
- consultas concorrentes
- centenas de conexões simultâneas
- latência A15 versus Motorola
- política automática de overflow de leitura
- impacto de consultas no primary durante escrita
- utilização de CPU
- utilização de RAM
- I/O do armazenamento
- temperatura
- thermal throttling
- consumo de energia
- estabilidade por longos períodos
- comportamento após perda de Wi-Fi
- recuperação da streaming replication
- reinicialização dos dispositivos
- comportamento após suspensão do Android
- diferenças entre fabricantes e kernels Android

---

# Estado experimental

Este projeto é experimental.

A execução bem-sucedida de PostgreSQL em smartphones Android não significa que qualquer aparelho seja adequado como servidor de produção.

O comportamento pode variar de acordo com:

```text
fabricante
modelo
SoC
arquitetura
Android
kernel
root
SELinux
userspace 32/64 bits
RAM
armazenamento
temperatura
gerenciamento de energia
Wi-Fi
```

O objetivo deste repositório é fornecer resultados reproduzíveis e um ponto de partida técnico para outras pessoas interessadas em explorar PostgreSQL, Android, ARM, chroot e computação distribuída.

---

# Documentação relacionada

Consulte também:

```text
../README.pt-BR.md
../chroot/README.pt-BR.md
../android-shmem/README.pt-BR.md
../scripts/README.pt-BR.md
```

Para a versão em inglês:

```text
README.md
```

---

# Conclusão

Os experimentos mostram que PostgreSQL 18.6 pode ser compilado e executado em Ubuntu 24.04 chroot hospedado por Android, tanto em ARM64 quanto em um ambiente ARMHF/32 bits testado.

A compatibilidade de memória compartilhada fornecida pelo `android-shmem` modificado foi uma parte essencial da implementação.

O Galaxy A15 e o Motorola demonstraram também que dois dispositivos Android ARM64 podem operar como primary e hot standby PostgreSQL utilizando streaming replication físico.

O LG K11 Plus demonstrou que o experimento pode ser levado também a um userspace ARMHF/32 bits, exigindo uma adaptação adicional relacionada a `__shmctl64`.

Além do funcionamento do banco, os experimentos ajudaram a demonstrar uma característica importante do modelo chroot: PostgreSQL é iniciado utilizando o userspace Ubuntu, mas seus processos continuam pertencendo ao kernel Linux compartilhado com Android. Sair do shell do chroot não implica encerrar o servidor.

O repositório continuará documentando não apenas os resultados positivos, mas também as limitações, falhas, diferenças entre arquiteturas e procedimentos necessários para reproduzir o ambiente.
