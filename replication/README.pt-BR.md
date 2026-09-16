# Streaming Replication PostgreSQL entre dispositivos Android

[English](README.md)

## Visão geral

Esta documentação descreve a configuração e a validação de streaming replication físico do PostgreSQL 18.6 entre dois dispositivos Android executando Ubuntu 24.04 LTS em ambientes chroot.

A configuração foi implementada e testada em dispositivos físicos utilizados durante o desenvolvimento deste projeto.

O ambiente atualmente comprovado utiliza:

- Samsung Galaxy A15 — ARM64 — PostgreSQL primary
- Motorola Android One (deen) — ARM64 — PostgreSQL hot standby

Os dois dispositivos executam:

```text
PostgreSQL 18.6
Ubuntu 24.04 LTS
ARM64 / 64 bits
````

O PostgreSQL foi compilado a partir do código-fonte em ambos os dispositivos e utiliza a biblioteca de compatibilidade `android-shmem` através de `LD_PRELOAD`.

A instalação segue a mesma estrutura nos dois aparelhos:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

A documentação da instalação e compilação do PostgreSQL encontra-se em:

```text
../postgresql/
```

A documentação do Ubuntu chroot encontra-se em:

```text
../chroot/
```

E a adaptação utilizada para memória compartilhada está documentada em:

```text
../android-shmem/
```

O objetivo desta seção é documentar especificamente a replicação entre os nós, incluindo a configuração do primary, criação do standby, validação do streaming e testes realizados nos dispositivos reais.

---

## Arquitetura testada

A topologia utilizada durante os testes foi:

```text
              rede local 192.168.1.0/24

        Galaxy A15                    Motorola Android One
        192.168.1.50                  192.168.1.40

        PRIMARY                       HOT STANDBY
        PostgreSQL 18.6               PostgreSQL 18.6
        Ubuntu 24.04                  Ubuntu 24.04
        ARM64 / 64 bits               ARM64 / 64 bits

             |
             | physical WAL streaming
             | asynchronous
             |
             +------------------------------->

                        SELECT permitido
                        INSERT recusado
```

O Galaxy A15 mantém o banco gravável e gera os registros WAL.

O Motorola recebe continuamente o WAL através do protocolo de streaming replication do PostgreSQL e permanece em recovery como hot standby.

Durante a validação, o primary identificou o Motorola através do endereço:

```text
192.168.1.40
```

e o standby identificou o servidor de origem através de:

```text
192.168.1.50:5432
```

---

## O que esta configuração representa

A configuração documentada neste diretório é uma implementação de:

```text
PostgreSQL physical streaming replication

PRIMARY
   |
   | WAL
   v
HOT STANDBY
```

Ela permite que as alterações realizadas no primary sejam reproduzidas fisicamente no standby.

Durante os testes foi comprovado que:

```text
INSERT no Galaxy A15
        |
        v
geração de WAL
        |
        v
streaming pela rede
        |
        v
recepção pelo Motorola
        |
        v
replay do WAL
        |
        v
SELECT disponível no hot standby
```

O standby permanece em modo somente leitura enquanto está em recovery.

Esta configuração, isoladamente, não deve ser confundida com uma solução completa de alta disponibilidade.

Até o estágio documentado atualmente, o projeto não implementa automaticamente:

```text
failover
eleição de primary
fencing
VIP
service discovery
redirecionamento automático de clientes
promoção automática do standby
reintegração automática do antigo primary
```

Esses mecanismos poderão ser investigados em etapas posteriores do projeto.

A distinção é importante porque o objetivo deste repositório é separar claramente aquilo que já foi executado e comprovado daquilo que ainda pertence à fase experimental futura.

---

## Ambiente dos dispositivos

### Galaxy A15 — primary

Durante a coleta utilizada para esta documentação, o Galaxy A15 apresentou:

```text
PostgreSQL 18.6
ARM64
64 bits
IP: 192.168.1.50
```

A função:

```sql
SELECT pg_is_in_recovery();
```

retornou:

```text
f
```

confirmando que o servidor não estava em recovery e estava operando como primary.

As configurações relevantes retornadas pelo próprio PostgreSQL foram:

```text
wal_level             = replica
max_wal_senders       = 10
max_replication_slots = 10
hot_standby           = on
listen_addresses      = *
```

---

### Motorola Android One — hot standby

Durante a mesma validação, o Motorola apresentou:

```text
PostgreSQL 18.6
ARM64
64 bits
IP: 192.168.1.40
```

A função:

```sql
SELECT pg_is_in_recovery();
```

retornou:

```text
t
```

confirmando que o servidor estava em recovery.

O arquivo:

```text
/usr/local/pgsql18/data/standby.signal
```

também estava presente.

O `pg_controldata` apresentou:

```text
Database cluster state: in archive recovery
```

Essas verificações, combinadas com o WAL receiver ativo, confirmaram o papel do Motorola como hot standby.

---

## Pré-requisitos

Antes de configurar a replicação, os dois dispositivos precisam possuir instalações PostgreSQL funcionais e compatíveis.

No ambiente testado foram utilizados:

```text
Ubuntu 24.04 LTS
PostgreSQL 18.6
ARM64 / 64 bits
android-shmem modificado
```

O PostgreSQL deve estar operacional individualmente em cada dispositivo antes da configuração da replicação.

Também é necessário que os aparelhos consigam se comunicar através da rede.

No laboratório utilizado pelo projeto:

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

Os endereços acima correspondem ao ambiente experimental e devem ser adaptados para a rede utilizada por quem reproduzir os testes.

A autenticação utilizada para a conexão de replicação foi:

```text
SCRAM-SHA-256
```
---

# Configuração do primary — Galaxy A15

O Galaxy A15 foi utilizado como servidor PostgreSQL primary.

No ambiente testado:

```text
Dispositivo: Samsung Galaxy A15
IP: 192.168.1.50
PostgreSQL: 18.6
Arquitetura: ARM64 / 64 bits
Função: PRIMARY
```

Antes da configuração da replicação, o PostgreSQL já estava instalado e funcionando através do Ubuntu chroot.

A instalação utilizada encontra-se em:

```text
/usr/local/pgsql18
```

e o diretório de dados em:

```text
/usr/local/pgsql18/data
```

---

## Configuração do postgresql.conf

No Galaxy A15, as configurações relevantes para a replicação foram adicionadas ao arquivo:

```text
/usr/local/pgsql18/data/postgresql.conf
```

A configuração utilizada é:

```conf
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
```

Durante a preparação desta documentação, essas configurações foram novamente verificadas diretamente no arquivo:

```bash
grep -nE \
'^[[:space:]]*(listen_addresses|port|wal_level|max_wal_senders|max_replication_slots|hot_standby)[[:space:]]*=' \
/usr/local/pgsql18/data/postgresql.conf
```

O resultado observado no Galaxy A15 foi:

```text
893:listen_addresses = '*'
894:wal_level = replica
895:max_wal_senders = 10
896:max_replication_slots = 10
897:hot_standby = on
```

Também foi feita a verificação através do próprio PostgreSQL:

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SHOW hot_standby;
SHOW listen_addresses;
```

Os valores retornados foram:

```text
wal_level             = replica
max_wal_senders       = 10
max_replication_slots = 10
hot_standby           = on
listen_addresses      = *
```

Dessa forma, a documentação não depende apenas da leitura do arquivo de configuração: os valores efetivamente carregados pelo servidor também foram confirmados.

---

## Significado das principais configurações

A opção:

```conf
wal_level = replica
```

faz com que o WAL contenha as informações necessárias para suportar replicação física.

A opção:

```conf
max_wal_senders = 10
```

permite processos WAL sender responsáveis pelo envio de WAL para standbys e outras conexões de replicação compatíveis.

No ambiente experimental foi mantido:

```conf
max_replication_slots = 10
```

Embora essa configuração esteja habilitada no servidor, a simples presença desse valor não significa que um replication slot esteja sendo utilizado pelo standby documentado aqui. O uso de slots deve ser verificado separadamente quando necessário.

A configuração:

```conf
listen_addresses = '*'
```

faz o PostgreSQL escutar nas interfaces disponíveis, permitindo a conexão do Motorola através da rede.

O controle de quais clientes podem efetivamente conectar continua sendo realizado pelo `pg_hba.conf` e pelos mecanismos de autenticação do PostgreSQL.

---

## Usuário de replicação

Foi utilizado um usuário PostgreSQL dedicado à replicação:

```text
replicador
```

Esse usuário possui o atributo:

```text
REPLICATION
```

Uma criação equivalente pode ser realizada no primary através de um comando como:

```sql
CREATE ROLE replicador
WITH REPLICATION
LOGIN
PASSWORD 'SUBSTITUA_POR_UMA_SENHA_FORTE';
```

O valor acima é apenas um placeholder.

**Não utilize essa senha literal.**

A senha real utilizada nos dispositivos experimentais não é armazenada neste repositório.

Para verificar os atributos de uma role sem expor sua senha, pode-se utilizar no `psql`:

```text
\du replicador
```

ou consultar apenas os atributos necessários através das views e catálogos do PostgreSQL.

---

## Configuração do pg_hba.conf

O acesso de replicação do Motorola foi autorizado no Galaxy A15 através de:

```text
/usr/local/pgsql18/data/pg_hba.conf
```

Durante a coleta realizada para esta documentação, a regra existente era:

```conf
host    replication    replicador    192.168.1.40/32    scram-sha-256
```

Essa regra possui significado específico:

```text
host
  |
  +-- conexão TCP/IP

replication
  |
  +-- conexão destinada à replicação

replicador
  |
  +-- usuário PostgreSQL autorizado

192.168.1.40/32
  |
  +-- somente o endereço do Motorola utilizado no teste

scram-sha-256
  |
  +-- método de autenticação
```

A utilização de `/32` limita essa regra especificamente ao endereço:

```text
192.168.1.40
```

em vez de liberar toda a rede local para o usuário de replicação.

No ambiente experimental havia também uma regra separada para conexões PostgreSQL normais provenientes da rede:

```conf
host    all    all    192.168.1.0/24    scram-sha-256
```

Essa regra não substitui a regra específica de replicação.

---

## Verificando as regras ativas do pg_hba.conf

Durante a documentação, as linhas não comentadas foram verificadas com:

```bash
grep -vE '^[[:space:]]*(#|$)' \
  /usr/local/pgsql18/data/pg_hba.conf
```

No Galaxy A15 foi observado:

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

Essas são as regras observadas no ambiente experimental e não devem ser copiadas indiscriminadamente para qualquer instalação.

Em particular, políticas de autenticação local devem ser avaliadas de acordo com os requisitos de segurança do ambiente onde PostgreSQL será executado.

---

## Reinicialização ou reload da configuração

Alterações em determinadas configurações do PostgreSQL podem exigir reinicialização do servidor.

Neste projeto, o gerenciamento do PostgreSQL é realizado pelos scripts:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

Para reiniciar utilizando o procedimento padronizado do projeto:

```bash
/scripts/postgres/restart.sh
```

Os scripts estão preservados no repositório em:

```text
../scripts/postgres/
```

---

## Confirmando que o Galaxy A15 é o primary

Depois da inicialização, foi executado:

```sql
SELECT pg_is_in_recovery();
```

No Galaxy A15 o resultado observado foi:

```text
f
```

Ou seja:

```text
pg_is_in_recovery() = false
```

Isso confirma que o servidor não estava executando em recovery.

Conceitualmente:

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

## Estado do primary sem o standby conectado

Um comportamento útil foi registrado durante a preparação desta documentação.

Com o PostgreSQL do Galaxy A15 em execução, mas antes da inicialização do PostgreSQL no Motorola, foi consultado:

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

O resultado foi:

```text
(0 rows)
```

Isso não indicava falha da configuração.

Naquele momento simplesmente não havia nenhum standby conectado ao WAL sender do primary.

Posteriormente, após a inicialização do Motorola, a mesma consulta passou a apresentar uma conexão de replicação ativa.

Essa diferença foi observada durante o mesmo procedimento de validação e será mostrada nas seções seguintes.

---

# Preparação do hot standby — Motorola

O Motorola Android One foi utilizado como hot standby do Galaxy A15.

No ambiente testado:

```text
Dispositivo: Motorola Android One (deen)
IP: 192.168.1.40
PostgreSQL: 18.6
Arquitetura: ARM64 / 64 bits
Função: HOT STANDBY
```

Assim como no Galaxy A15, o PostgreSQL foi compilado e instalado em:

```text
/usr/local/pgsql18
```

O diretório utilizado pelo cluster PostgreSQL é:

```text
/usr/local/pgsql18/data
```

Antes de transformar uma instalação existente em standby, qualquer diretório de dados importante deve ser preservado.

**Nunca substitua um `PGDATA` contendo dados que ainda sejam necessários sem possuir um backup verificado.**

---

## Origem dos dados do standby

Streaming replication físico não cria inicialmente uma cópia completa do banco apenas conectando o standby ao primary.

O Motorola precisa partir de uma cópia consistente do cluster do Galaxy A15.

Para isso, o PostgreSQL fornece:

```text
pg_basebackup
```

Conceitualmente:

```text
Galaxy A15
PRIMARY
192.168.1.50
     |
     | pg_basebackup
     |
     | cópia física inicial
     v
Motorola
192.168.1.40
     |
     v
PGDATA
```

Depois dessa cópia inicial, as alterações posteriores podem ser recebidas através do streaming de WAL.

---

## Parando PostgreSQL antes de substituir o PGDATA

O PostgreSQL do Motorola não deve estar utilizando o diretório de dados enquanto ele estiver sendo preparado para receber o base backup.

No projeto, o servidor pode ser parado através de:

```bash
/scripts/postgres/stop.sh
```

e seu estado pode ser verificado com:

```bash
/scripts/postgres/status.sh
```

Antes de remover ou renomear qualquer diretório de dados existente, confirme que PostgreSQL realmente foi encerrado.

---

## Preservando um PGDATA existente

Se o Motorola já possuir um cluster PostgreSQL que precise ser preservado, uma abordagem possível é renomeá-lo antes do `pg_basebackup`.

Exemplo:

```bash
mv /usr/local/pgsql18/data \
   /usr/local/pgsql18/data.backup
```

Depois pode ser criado novamente o destino:

```bash
mkdir /usr/local/pgsql18/data
chown postgres:postgres /usr/local/pgsql18/data
chmod 700 /usr/local/pgsql18/data
```

O nome:

```text
data.backup
```

é apenas um exemplo.

Antes de executar esse procedimento em um ambiente contendo informações importantes, confirme espaço disponível e existência de backup independente.

---

## Executando pg_basebackup

O `pg_basebackup` deve ser executado no dispositivo que será o standby, conectando-se ao primary.

No ambiente deste projeto:

```text
Primary: 192.168.1.50
Porta:   5432
Usuário: replicador
Destino: /usr/local/pgsql18/data
```

Uma forma reproduzível de executar a cópia é:

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

As opções utilizadas nesse exemplo possuem os seguintes propósitos:

```text
-h 192.168.1.50
    primary

-p 5432
    porta PostgreSQL

-U replicador
    usuário dedicado à replicação

-D /usr/local/pgsql18/data
    diretório de destino

-Fp
    formato plain

-Xs
    WAL transferido por streaming durante o backup

-P
    mostra progresso

-R
    prepara o destino para operar como standby
```

A senha do usuário `replicador`, quando solicitada, deve ser fornecida de forma segura.

Não coloque a senha real diretamente em documentação pública, scripts versionados ou exemplos destinados ao GitHub.

---

## Sobre a opção -R

A opção:

```text
-R
```

é especialmente importante na preparação do standby.

Ela faz com que `pg_basebackup` crie os elementos necessários para que o cluster resultante tente iniciar como standby.

Entre eles está:

```text
standby.signal
```

e são adicionadas informações de conexão com o primary à configuração apropriada do PostgreSQL.

No Motorola utilizado neste projeto, foi posteriormente comprovada a existência de:

```text
/usr/local/pgsql18/data/standby.signal
```

Durante a coleta realizada para esta documentação:

```bash
ls -lh /usr/local/pgsql18/data/standby.signal
```

retornou um arquivo pertencente a:

```text
postgres:postgres
```

com tamanho:

```text
0 bytes
```

O conteúdo do arquivo não é importante; sua existência é utilizada pelo PostgreSQL para determinar o comportamento de standby na inicialização.

---

## primary_conninfo e segurança

A preparação do standby pode resultar em informações de conexão com o primary armazenadas em:

```text
postgresql.auto.conf
```

Entre essas informações pode existir:

```text
primary_conninfo
```

e essa configuração pode conter credenciais.

Por esse motivo:

**não publique o `postgresql.auto.conf` real de um standby sem antes verificar cuidadosamente seu conteúdo.**

Um exemplo destinado à documentação deve utilizar apenas valores fictícios:

```conf
primary_conninfo = 'host=192.168.1.50 port=5432 user=replicador password=SUBSTITUA_PELA_SENHA_REAL'
```

O exemplo acima não contém a senha utilizada neste projeto.

Nunca copie a credencial real do laboratório para o repositório Git.

---

## Permissões do diretório de dados

Depois do base backup, o diretório deve continuar pertencendo ao usuário PostgreSQL.

No ambiente utilizado:

```text
postgres:postgres
```

As permissões do `PGDATA` são restritas:

```text
drwx------
```

Pode-se verificar com:

```bash
ls -ld /usr/local/pgsql18/data
```

O usuário utilizado pelo projeto é:

```text
uid=1000(postgres)
gid=1000(postgres)
```

As particularidades desse UID no Android estão documentadas em:

```text
../postgresql/README.pt-BR.md
```

---

## Inicializando o standby

Depois da preparação do `PGDATA`, PostgreSQL pode ser iniciado através do script padronizado:

```bash
/scripts/postgres/start.sh
```

O script utiliza:

```text
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

e executa PostgreSQL com os parâmetros de usuário e grupos utilizados pelo projeto.

A estrutura relevante é:

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

Os scripts reais estão preservados em:

```text
../scripts/postgres/
```

---

# Verificação do hot standby

Depois da inicialização do Motorola, uma das primeiras verificações é:

```sql
SELECT pg_is_in_recovery();
```

Durante a coleta realizada para esta documentação, o resultado no Motorola foi:

```text
 pg_is_in_recovery
-------------------
 t
(1 row)
```

Portanto:

```text
pg_is_in_recovery() = true
```

Isso confirma que o cluster está executando em recovery.

Conceitualmente:

```text
Motorola
192.168.1.40

standby.signal
      |
      v
PostgreSQL inicia
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

## Verificação com pg_controldata

Também foi utilizado:

```bash
/usr/local/pgsql18/bin/pg_controldata \
  /usr/local/pgsql18/data
```

Durante a coleta no Motorola foi observado:

```text
Database system identifier: 7676117900798732860
Database cluster state: in archive recovery
```

Também foram registrados:

```text
Latest checkpoint location:        1/F37F8E30
Latest checkpoint's REDO location: 1/F37F8DD8
Latest checkpoint's REDO WAL file: 0000000100000001000000F3
Latest checkpoint's TimeLineID:     1
Latest checkpoint's PrevTimeLineID: 1
```

Esses valores correspondem ao estado observado naquele momento e não devem ser tratados como valores fixos de uma instalação PostgreSQL.

LSNs, arquivos WAL, XIDs, checkpoints e outros identificadores mudam conforme o banco é utilizado.

O objetivo de preservá-los aqui é registrar evidência do estado real observado durante o experimento.

---

# Verificando o WAL receiver

No Motorola foi executada a consulta:

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

Durante a validação, o resultado foi:

```text
status         = streaming
sender_host    = 192.168.1.50
sender_port    = 5432
written_lsn    = 1/F37FE218
flushed_lsn    = 1/F37FE218
latest_end_lsn = 1/F37FE218
```

Essa consulta fornece evidência direta do lado do standby de que existe um WAL receiver conectado ao Galaxy A15.

A relação observada foi:

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

# Verificação da replicação pelo primary

Depois da inicialização do Motorola, o Galaxy A15 passou a apresentar uma conexão ativa em:

```text
pg_stat_replication
```

A consulta utilizada foi:

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

Durante a coleta realizada para esta documentação, o resultado observado no Galaxy A15 foi:

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

Isso confirma, pelo lado do primary, que o Motorola estava conectado e recebendo WAL através de streaming replication.

A mesma consulta havia retornado:

```text
(0 rows)
```

antes da inicialização do Motorola.

Portanto, durante o mesmo procedimento de validação foram observados os dois estados:

```text
Motorola sem PostgreSQL conectado
        |
        v
pg_stat_replication
        |
        +-- 0 rows


Motorola iniciado
        |
        v
WAL receiver conecta ao A15
        |
        v
pg_stat_replication
        |
        +-- client_addr = 192.168.1.40
        +-- state       = streaming
        +-- sync_state  = async
```

---

## Replicação assíncrona

No Galaxy A15 foi observado:

```text
sync_state = async
```

Portanto, a replicação testada neste projeto estava operando de forma assíncrona.

Conceitualmente:

```text
Aplicação
    |
    v
Galaxy A15
PRIMARY
    |
    +-- COMMIT no primary
    |
    +-- WAL
          |
          | streaming assíncrono
          v
       Motorola
       HOT STANDBY
```

Em replicação assíncrona, o commit no primary não depende necessariamente da confirmação de que o standby já persistiu ou reproduziu aquele WAL.

Consequentemente, a existência de streaming replication não deve ser interpretada como garantia de perda zero de dados diante de qualquer tipo de falha.

Essa distinção será importante em futuros experimentos de failover e alta disponibilidade.

---

# Comparação dos LSNs observados

Durante a coleta, o Galaxy A15 apresentou:

```text
sent_lsn   = 1/F37FE218
write_lsn  = 1/F37FE218
flush_lsn  = 1/F37FE218
replay_lsn = 1/F37FE218
```

No mesmo período, o Motorola apresentou através de `pg_stat_wal_receiver`:

```text
written_lsn    = 1/F37FE218
flushed_lsn    = 1/F37FE218
latest_end_lsn = 1/F37FE218
```

Assim, naquele instante específico da observação:

```text
Galaxy A15                         Motorola

sent_lsn      1/F37FE218  ------> latest_end_lsn 1/F37FE218
write_lsn     1/F37FE218           written_lsn    1/F37FE218
flush_lsn     1/F37FE218           flushed_lsn    1/F37FE218
replay_lsn    1/F37FE218
```

Os valores iguais mostram que, naquele momento da consulta, o standby havia alcançado o ponto WAL apresentado pelo primary.

Isso **não significa que os LSNs permanecerão sempre iguais**.

Durante períodos de escrita intensa, atraso de rede, carga elevada ou replay mais lento, esses valores podem divergir temporariamente.

Portanto, o resultado deve ser interpretado como uma fotografia do estado da replicação naquele instante, e não como uma garantia permanente de ausência de lag.

---

## Checkpoint não é o mesmo que posição atual do streaming

No Motorola, `pg_controldata` apresentou:

```text
Latest checkpoint location: 1/F37F8E30
```

enquanto `pg_stat_wal_receiver` apresentou:

```text
latest_end_lsn = 1/F37FE218
```

Esses valores não precisam ser iguais.

A posição do último checkpoint e a posição mais recente recebida através do streaming representam informações diferentes sobre o estado interno do PostgreSQL.

Por isso, a diferença entre esses valores não deve ser interpretada isoladamente como atraso da réplica.

Para acompanhar a replicação devem ser utilizadas as views e funções apropriadas do PostgreSQL, incluindo:

```text
pg_stat_replication
pg_stat_wal_receiver
```

---

# Teste real de replicação

Depois de confirmar o estado `streaming` pelos dois lados, foi realizado um teste específico para esta documentação.

O objetivo foi comprovar o fluxo completo:

```text
escrita no primary
        |
        v
WAL
        |
        v
streaming replication
        |
        v
replay no standby
        |
        v
leitura no standby
```

---

## Criação da tabela no Galaxy A15

No Galaxy A15 primary foi criada:

```sql
CREATE TABLE IF NOT EXISTS replication_documentation_test
(
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origem text NOT NULL,
    mensagem text NOT NULL,
    criado_em timestamptz NOT NULL DEFAULT now()
);
```

Em seguida foi inserido:

```sql
INSERT INTO replication_documentation_test
    (origem, mensagem)
VALUES
    ('Galaxy A15', 'Physical streaming replication test A15 -> Motorola');
```

A operação foi executada no primary.

---

## Consulta no Motorola

Depois da inserção no Galaxy A15, no Motorola hot standby foi executado:

```sql
SELECT *
FROM replication_documentation_test
ORDER BY id DESC
LIMIT 5;
```

O Motorola retornou:

```text
id       = 1
origem   = Galaxy A15
mensagem = Physical streaming replication test A15 -> Motorola
```

A linha também apresentou o timestamp correspondente à inserção realizada durante o teste.

Isso demonstrou que tanto a definição da tabela quanto a linha inserida no Galaxy A15 haviam chegado ao Motorola através da replicação física.

Conceitualmente:

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
linha encontrada
```

---

# Comprovação do modo somente leitura no hot standby

Foi realizado também o teste inverso.

Depois de comprovar que o Motorola conseguia consultar a linha replicada, tentou-se executar diretamente nele:

```sql
INSERT INTO replication_documentation_test
    (origem, mensagem)
VALUES
    ('Motorola', 'This INSERT should fail on the hot standby');
```

O PostgreSQL respondeu:

```text
ERROR: cannot execute INSERT in a read-only transaction
```

Em seguida foi executado:

```sql
SHOW transaction_read_only;
```

O resultado foi:

```text
transaction_read_only
----------------------
on
```

Também foi novamente verificado:

```sql
SELECT pg_is_in_recovery();
```

com resultado:

```text
pg_is_in_recovery
------------------
t
```

Assim, durante o mesmo teste foi comprovado:

```text
Motorola HOT STANDBY

SELECT
   |
   +-- permitido

INSERT
   |
   +-- recusado
       "cannot execute INSERT
        in a read-only transaction"

transaction_read_only = on

pg_is_in_recovery() = true
```

Esse comportamento é consistente com o papel do dispositivo como hot standby durante o recovery.

---

# Evidências observadas pelos dois lados

As verificações realizadas permitem observar a mesma sessão de replicação a partir dos dois dispositivos.

No Galaxy A15:

```text
pg_is_in_recovery() = false

pg_stat_replication:

application_name = walreceiver
client_addr      = 192.168.1.40
state            = streaming
sync_state       = async
```

No Motorola:

```text
pg_is_in_recovery() = true
transaction_read_only = on

pg_stat_wal_receiver:

status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

Além disso:

```text
standby.signal = presente

Database cluster state =
in archive recovery
```

A relação completa observada foi:

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

# Consultas no hot standby

Uma consequência importante dessa arquitetura é que o Motorola pode executar consultas enquanto continua recebendo e reproduzindo WAL.

Isso abre espaço para experimentos de distribuição de leitura.

Uma arquitetura futura investigada pelo projeto é:

```text
                    aplicações
                        |
                        v
                  camada de decisão
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

No estágio atual, essa distribuição automática de consultas ainda não foi implementada.

O que já foi comprovado é que o hot standby consegue responder a consultas sobre os dados replicados.

A estratégia de roteamento, detecção de carga e overflow de leitura permanece como trabalho experimental futuro.

---

# Limites da demonstração atual

Os testes documentados comprovam streaming replication físico funcional entre os dois dispositivos Android.

Eles não comprovam, por si só:

```text
failover automático
RPO zero
RTO específico
alta disponibilidade completa
eleição automática de primary
proteção contra split-brain
fencing
balanceamento automático
reintegração automática
garantia de desempenho sob qualquer carga
```

Esses mecanismos exigem experimentos e componentes adicionais.

A documentação mantém essa separação para que resultados já comprovados não sejam confundidos com objetivos futuros.

---

# Comportamento quando o standby está desconectado

Durante a preparação desta documentação foi observado o primary funcionando sem nenhum standby conectado.

No Galaxy A15, com PostgreSQL em execução e o Motorola ainda desconectado, a consulta:

```sql
SELECT
    application_name,
    client_addr,
    state,
    sync_state
FROM pg_stat_replication;
```

não apresentou nenhuma conexão:

```text
(0 rows)
```

O Galaxy A15 continuou funcionando normalmente como primary.

Depois da inicialização do PostgreSQL no Motorola, a conexão apareceu em `pg_stat_replication`:

```text
application_name = walreceiver
client_addr      = 192.168.1.40
state            = streaming
sync_state       = async
```

Isso demonstra, no ambiente testado, que o primary não depende da presença permanente do standby para permanecer operacional.

Essa característica é coerente com a configuração assíncrona utilizada.

---

## Reconexão do standby

Quando o Motorola está disponível e consegue alcançar o Galaxy A15, seu WAL receiver conecta-se ao primary.

A relação observada durante os testes foi:

```text
Motorola indisponível
        |
        v
Galaxy A15 continua como PRIMARY
        |
        v
pg_stat_replication = 0 rows


Motorola inicia PostgreSQL
        |
        v
standby.signal detectado
        |
        v
recovery
        |
        v
WAL receiver conecta ao primary
        |
        v
state = streaming
```

O comportamento exato após períodos maiores de desconexão depende da disponibilidade dos segmentos WAL necessários para que o standby alcance novamente o primary.

Por esse motivo, a simples reconexão observada nos testes atuais não deve ser interpretada como garantia de recuperação automática após qualquer duração ou tipo de interrupção.

---

# Retenção de WAL e recuperação após interrupções

Um standby precisa ter acesso aos registros WAL necessários para continuar seu processo de recovery.

Se um standby permanecer desconectado por tempo suficiente e os segmentos WAL necessários deixarem de estar disponíveis no primary, a recuperação poderá exigir intervenção.

Esse aspecto será importante nos próximos experimentos do projeto.

Entre as estratégias PostgreSQL que podem ser investigadas estão:

```text
replication slots
wal_keep_size
WAL archive
restore_command
novo pg_basebackup
```

A configuração atual apresenta:

```text
max_replication_slots = 10
```

mas esse valor apenas permite a criação de replication slots.

Ele não comprova que o Motorola esteja atualmente utilizando um slot.

Antes de documentar utilização de replication slots neste projeto, seu uso real deverá ser configurado e verificado experimentalmente.

---

# Monitoramento da replicação

O estado da replicação pode ser acompanhado tanto pelo primary quanto pelo standby.

## No primary

A principal view utilizada nos testes foi:

```text
pg_stat_replication
```

Exemplo:

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

Ela permite observar informações como:

```text
standby conectado
endereço do standby
estado da conexão
modo síncrono ou assíncrono
posição WAL enviada
posição escrita
posição persistida
posição reproduzida
```

No ambiente testado:

```text
client_addr = 192.168.1.40
state       = streaming
sync_state  = async
```

---

## No standby

No Motorola foi utilizada:

```text
pg_stat_wal_receiver
```

Exemplo:

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

Durante o teste:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

Também são verificações úteis:

```sql
SELECT pg_is_in_recovery();

SHOW transaction_read_only;
```

No Motorola foram observados:

```text
pg_is_in_recovery() = true
transaction_read_only = on
```

---

# Medindo atraso de replicação

A igualdade dos LSNs observada durante um teste não deve ser utilizada como única forma de avaliar permanentemente a saúde da replicação.

Em futuros benchmarks poderão ser comparadas posições WAL e, quando aplicável, informações temporais disponíveis nas views do PostgreSQL.

No primary, por exemplo, podem ser observadas diferenças entre:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

Uma situação conceitual possível é:

```text
sent_lsn
    |
    | WAL enviado
    v
write_lsn
    |
    | WAL escrito no standby
    v
flush_lsn
    |
    | WAL persistido
    v
replay_lsn
    |
    | WAL aplicado
    v
dados disponíveis no standby
```

A interpretação dessas posições deve considerar carga, rede, armazenamento e atividade do banco.

---

# Replicação e distribuição de consultas

Um dos objetivos experimentais do projeto é avaliar se smartphones Android podem funcionar como pequenos nós PostgreSQL distribuídos.

A existência de um hot standby funcional permite investigar uma arquitetura em que consultas de leitura possam utilizar mais de um dispositivo.

A ideia inicial é manter o Galaxy A15 como primary e utilizá-lo também para consultas enquanto houver capacidade disponível.

Conceitualmente:

```text
                       clientes
                           |
                           v
                    consultas SELECT
                           |
                           v
                     Galaxy A15
                       PRIMARY
                           |
                capacidade disponível?
                    /             \
                  sim             não
                   |               |
                   v               v
             SELECT no A15     novo SELECT
                                   |
                                   v
                               Motorola
                              HOT STANDBY
```

A motivação não é simplesmente enviar todas as leituras para o standby.

O primary também possui capacidade de processamento que pode ser utilizada.

O objetivo futuro é investigar quando a carga de leitura no Galaxy A15 começa a produzir contenção suficiente para justificar o encaminhamento de novas consultas ao Motorola.

---

## Relação com a carga de ingestão

No sistema que motivou esses experimentos, grandes volumes de dados podem ser ingeridos em determinados períodos.

Isso torna interessante estudar separadamente:

```text
carga de escrita
carga de leitura
concorrência entre escrita e leitura
capacidade ociosa do primary
capacidade adicional do standby
```

Uma possível estratégia experimental é:

```text
período de maior ingestão
        |
        v
Galaxy A15
PRIMARY
escrita predominante
        |
        +------------------+
                           |
                           v
                       Motorola
                      HOT STANDBY
                       consultas


período de menor ingestão
        |
        v
Galaxy A15
PRIMARY
        |
        +-- SELECT
        |
        +-- escrita residual

Motorola
HOT STANDBY
        |
        +-- capacidade adicional de SELECT
```

Essa política ainda não foi implementada automaticamente.

Ela representa uma direção de pesquisa para benchmarks futuros.

---

# Do primary + hot standby para um cluster experimental

A configuração atualmente comprovada constitui uma base para experimentos mais amplos.

O estágio atual pode ser representado como:

```text
ESTÁGIO COMPROVADO

Galaxy A15
PRIMARY
     |
     | physical streaming replication
     | asynchronous
     v
Motorola
HOT STANDBY
```

Uma evolução possível é adicionar uma camada responsável por decidir onde executar consultas:

```text
ETAPA EXPERIMENTAL FUTURA

                    clientes
                        |
                        v
                  query router
                   /       \
                  /         \
                 v           v
          Galaxy A15      Motorola
            PRIMARY      HOT STANDBY
              |              |
           leitura         leitura
           escrita
```

Depois disso poderão ser investigados mecanismos de disponibilidade:

```text
                 monitoramento
                      |
                      v
              estado dos nós
                      |
          +-----------+-----------+
          |                       |
          v                       v
      PRIMARY                 HOT STANDBY
          |
          |
     falha detectada
          |
          v
   decisão de failover
          |
          v
 promoção controlada
```

Esses diagramas representam objetivos experimentais, e não funcionalidades já implementadas.

---

# Por que failover exige cuidados adicionais

Promover um standby é apenas uma parte de uma arquitetura de alta disponibilidade.

Uma solução mais completa precisa responder a questões como:

```text
Como detectar corretamente que o primary falhou?

Quem decide promover o standby?

Como evitar duas instâncias aceitando escrita?

Como impedir split-brain?

Como os clientes descobrem o novo primary?

O que acontece quando o antigo primary retorna?

Como o antigo primary será reintegrado?

Como garantir que ele não volte aceitando escrita com dados divergentes?

Qual é o RPO aceitável?

Qual é o RTO aceitável?
```

Por isso, o projeto não considera a existência de streaming replication suficiente para declarar alta disponibilidade completa.

Essas questões serão tratadas como experimentos separados.

---

# Split-brain

Um dos riscos que deverá ser considerado em experimentos futuros de failover é o chamado:

```text
split-brain
```

Conceitualmente, uma situação perigosa seria:

```text
          perda de comunicação
                 |
        +--------+--------+
        |                 |
        v                 v
     Nó A               Nó B
 acredita ser         promovido para
  PRIMARY               PRIMARY
        |                 |
        v                 v
     escrita             escrita
```

Se dois nós aceitarem escritas independentes, os históricos podem divergir.

Por isso, qualquer implementação futura de failover automático deverá considerar mecanismos de coordenação e isolamento antes de permitir promoção automática.

---

# Fencing

Em arquiteturas de alta disponibilidade, mecanismos de fencing podem ser utilizados para impedir que um nó considerado antigo ou inválido continue atuando como servidor gravável.

No contexto de dispositivos Android, esse tema possui particularidades interessantes porque os nós são smartphones independentes, com seus próprios:

```text
kernel Android
Wi-Fi
armazenamento
bateria
gerenciamento de energia
estado de suspensão
```

Nenhum mecanismo de fencing foi implementado até o momento neste projeto.

O assunto será investigado antes de qualquer tentativa de failover automático.

---

# Monitoramento futuro dos nós

Uma camada futura de monitoramento poderá observar informações como:

```text
dispositivo online/offline
PostgreSQL online/offline
papel primary/standby
estado do WAL receiver
estado do WAL sender
replication lag
CPU
RAM
I/O
temperatura
Wi-Fi
espaço disponível
energia/bateria
thermal throttling
```

No ambiente Android, algumas dessas métricas poderão ser obtidas pelo Ubuntu chroot, enquanto outras poderão precisar ser consultadas diretamente através do Android ou de `/sys`.

A arquitetura experimental poderá, portanto, combinar informações PostgreSQL com informações do dispositivo físico.

---

# Características particulares de um cluster baseado em smartphones

A utilização de smartphones como nós PostgreSQL apresenta diferenças importantes em relação a servidores convencionais.

Entre elas:

```text
Wi-Fi como rede principal
armazenamento flash móvel
limites térmicos mais agressivos
gerenciamento de energia do Android
bateria
suspensão
possível encerramento de processos pelo sistema
diferenças entre kernels dos fabricantes
SELinux
root
arquiteturas ARM diferentes
userspaces 32 e 64 bits
```

Essas características não tornam automaticamente os dispositivos inadequados para experimentação.

Elas representam variáveis adicionais que precisam ser medidas e documentadas.

---

# Arquiteturas diferentes e o papel do LG K11 Plus

A replicação física atualmente comprovada pelo projeto ocorre entre dois dispositivos ARM64/64 bits:

```text
Galaxy A15
ARM64 / 64 bits
PostgreSQL 18.6
PRIMARY

        |
        | physical streaming replication
        v

Motorola Android One
ARM64 / 64 bits
PostgreSQL 18.6
HOT STANDBY
```

O LG K11 Plus possui uma arquitetura diferente:

```text
LG K11 Plus
ARMHF / 32 bits
PostgreSQL 18.6
```

O PostgreSQL 18.6 foi compilado e executado com sucesso nesse dispositivo, mas o LG não faz parte da replicação física utilizada entre o Galaxy A15 e o Motorola.

---

## Replicação lógica testada no LG

Também foi experimentada replicação lógica entre o PostgreSQL principal e o LG K11 Plus.

O teste demonstrou que essa abordagem introduzia dependências administrativas no primary que não eram desejáveis para a arquitetura deste projeto.

Durante os experimentos, enquanto existiam objetos de replicação lógica associados ao banco utilizado pelo LG, determinadas operações administrativas no primary, incluindo a tentativa de exclusão do banco envolvido na configuração de replicação, eram bloqueadas até que as dependências correspondentes fossem tratadas.

Para o objetivo deste projeto, esse comportamento adicionava complexidade operacional sem fornecer uma vantagem suficiente para justificar a utilização do LG como réplica.

A replicação lógica com o LG foi, portanto, descartada da arquitetura planejada.

Essa decisão é específica aos objetivos e aos experimentos deste projeto e não significa que replicação lógica PostgreSQL seja inadequada de forma geral.

---

# Papel atual do LG K11 Plus

O LG permanece útil como dispositivo PostgreSQL independente e como nó auxiliar de processamento.

A arquitetura planejada passa a separar claramente os papéis:

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
                 nó independente
                        |
              processamento auxiliar
```

O LG poderá executar tarefas auxiliares que não dependam de fazer parte da replicação do cluster principal.

Possíveis experimentos incluem:

```text
processamento de dados
transformações
extrações
tarefas em lote
consultas sobre bases locais independentes
armazenamento temporário
processamento intermediário
workers auxiliares
```

Quando PostgreSQL for útil para determinada tarefa, o próprio PostgreSQL 18.6 já compilado no LG poderá ser utilizado como banco local independente.

---

## Separação entre replicação e processamento

Com essa decisão, a arquitetura experimental fica conceitualmente dividida em dois grupos:

```text
NÓS POSTGRESQL REPLICADOS

Galaxy A15
PRIMARY
   |
   | WAL
   v
Motorola
HOT STANDBY


NÓ AUXILIAR

LG K11 Plus
ARMHF / 32-bit
   |
   +-- processamento
   +-- tarefas em lote
   +-- workers
   +-- banco PostgreSQL local quando necessário
```

Essa separação evita introduzir no primary dependências de replicação com o LG apenas para aproveitar sua capacidade computacional.

O dispositivo pode contribuir para o sistema sem precisar manter uma cópia replicada do banco principal.

---

## Decisão atual do projeto

Com base nos experimentos realizados, a arquitetura adotada atualmente é:

```text
Galaxy A15
    |
    +-- PostgreSQL PRIMARY
    +-- escrita
    +-- leitura
    |
    +-------- physical streaming replication --------+
                                                       |
                                                       v
                                                   Motorola
                                                 HOT STANDBY
                                                 leitura adicional


LG K11 Plus
    |
    +-- PostgreSQL independente, quando necessário
    +-- processamento auxiliar
    +-- sem participação na replicação do primary
```

Portanto, futuros experimentos de replicação e alta disponibilidade serão concentrados inicialmente no par:

```text
Galaxy A15 <-> Motorola
```

O LG será tratado separadamente como nó auxiliar de processamento.

---

## Futuro teste de replicação física ARMHF/32 bits

O fato de o LG K11 Plus não participar atualmente da replicação física não encerra os experimentos de replicação em dispositivos 32 bits.

Uma possibilidade futura é utilizar dois dispositivos com ambientes compatíveis:

```text
Dispositivo ARMHF / 32-bit
PostgreSQL 18.6
PRIMARY

        |
        | physical streaming replication
        v

Dispositivo ARMHF / 32-bit
PostgreSQL 18.6
HOT STANDBY
```

Esse experimento permitiria investigar separadamente a replicação física PostgreSQL em smartphones Android utilizando userspace ARMHF/32 bits.

O LG K11 Plus poderia então participar de um novo ambiente experimental caso outro dispositivo compatível seja preparado.

Antes desse teste deverão ser verificadas cuidadosamente as condições necessárias para compatibilidade física entre os clusters, incluindo:

```text
arquitetura
userspace
versão do PostgreSQL
formato dos dados
configuração de compilação
bibliotecas utilizadas
ambiente Android/chroot
```

Portanto, o estado atual do projeto pode ser resumido como:

```text
COMPROVADO

ARM64 / 64-bit
Galaxy A15 PRIMARY
        |
        | physical streaming replication
        v
Motorola HOT STANDBY


TESTADO E DESCARTADO PARA A ARQUITETURA ATUAL

Galaxy A15
        |
        | logical replication
        v
LG K11 Plus ARMHF / 32-bit


POSSÍVEL EXPERIMENTO FUTURO

ARMHF / 32-bit
PRIMARY
        |
        | physical streaming replication
        v
ARMHF / 32-bit
HOT STANDBY
```

A replicação física ARMHF/32 bits ainda não foi testada neste projeto e, portanto, permanece como uma linha de investigação futura.

---

# Segurança da replicação

A replicação utiliza uma conexão PostgreSQL real entre dispositivos da rede e, portanto, deve ser tratada com os mesmos cuidados de qualquer servidor PostgreSQL.

No ambiente documentado, o Galaxy A15 possui uma regra específica para permitir a conexão de replicação proveniente do Motorola:

```text
host replication replicador 192.168.1.40/32 scram-sha-256
```

Essa regra restringe a conexão de replicação ao endereço utilizado pelo Motorola.

O restante das regras de acesso deve ser definido de acordo com as necessidades de cada ambiente.

---

## Credenciais

O usuário utilizado para replicação possui atributo:

```text
REPLICATION
```

Nenhuma senha real utilizada durante os experimentos deve ser armazenada neste repositório.

Especialmente, deve-se tomar cuidado com:

```text
postgresql.auto.conf
primary_conninfo
.pgpass
scripts
arquivos de configuração
histórico de comandos
backups
```

Um `postgresql.auto.conf` criado durante a preparação de um standby pode conter informações sensíveis.

Antes de publicar qualquer arquivo relacionado à replicação, revise seu conteúdo.

---

# Estado atualmente comprovado

Até o momento, os experimentos demonstraram diretamente:

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

Foram comprovados:

- PostgreSQL 18.6 executando nos dois dispositivos;
- primary e standby utilizando Ubuntu 24.04 chroot;
- `android-shmem` carregado através de `LD_PRELOAD`;
- `wal_level = replica`;
- conexão do WAL receiver;
- `state = streaming`;
- `sync_state = async`;
- `pg_is_in_recovery() = false` no primary;
- `pg_is_in_recovery() = true` no standby;
- presença de `standby.signal`;
- estado `in archive recovery` no Motorola;
- recebimento e replay de WAL;
- leitura de dados replicados no hot standby;
- tentativa de `INSERT` recusada no standby;
- `transaction_read_only = on` no Motorola;
- funcionamento do primary quando o standby está desconectado;
- reconexão do standby observada durante os testes.

Também foi realizado um teste funcional completo:

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
SELECT da linha replicada
```

---

# O que ainda não foi comprovado

A configuração atual não deve ser confundida com uma solução completa de alta disponibilidade.

Ainda não foram comprovados neste projeto:

```text
failover automático
failover manual documentado de ponta a ponta
failback
reintegração do antigo primary
fencing
proteção contra split-brain
RPO determinado
RTO determinado
replication slot para o Motorola
WAL archive para recuperação do standby
recuperação após perda prolongada de WAL
balanceamento automático de consultas
detecção automática de sobrecarga
promoção automática
cluster manager
```

Esses itens serão tratados separadamente conforme forem efetivamente testados.

---

# Próximos testes do cluster ARM64

O par Galaxy A15 e Motorola fornece uma base para novos experimentos.

Entre os próximos testes planejados estão:

```text
1. medir replication lag durante escrita intensa

2. interromper o Wi-Fi do Motorola e medir a recuperação

3. manter o standby desconectado por períodos progressivamente maiores

4. observar retenção e recuperação de WAL

5. testar replication slots

6. testar wal_keep_size

7. avaliar WAL archive

8. reiniciar o Motorola durante streaming

9. reiniciar o Galaxy A15

10. medir comportamento após suspensão do Android

11. executar SELECTs concorrentes no primary

12. executar SELECTs concorrentes no standby

13. executar escrita intensa no primary enquanto o standby recebe consultas

14. medir CPU, RAM e I/O nos dois dispositivos

15. medir temperatura e thermal throttling

16. medir comportamento com grande volume de WAL

17. testar promoção manual controlada do Motorola

18. estudar reintegração do antigo primary
```

Cada resultado será documentado somente depois de ser reproduzido no ambiente real.

---

# Futuro roteamento de consultas

Uma das linhas de pesquisa mais importantes será determinar quando utilizar o Motorola para aliviar consultas do Galaxy A15.

A intenção não é simplesmente direcionar todos os `SELECT` para o standby.

Uma estratégia possível é utilizar inicialmente o primary:

```text
                     SELECT
                        |
                        v
                   Galaxy A15
                     PRIMARY
                        |
                 carga aceitável?
                  /           \
                sim           não
                 |             |
                 v             v
             executa       encaminha
             no A15            |
                               v
                           Motorola
                          HOT STANDBY
```

Para implementar algo semelhante de forma responsável, primeiro será necessário medir quais indicadores realmente representam saturação no ambiente dos smartphones.

Possíveis indicadores incluem:

```text
CPU
load average
RAM disponível
I/O
tempo médio das consultas
número de consultas concorrentes
conexões PostgreSQL
replication lag
temperatura
thermal throttling
```

A decisão de roteamento deverá ser baseada em benchmarks, e não apenas em um limite arbitrário de utilização de CPU.

---

# Nós auxiliares fora da replicação

Nem todo dispositivo precisa fazer parte da replicação para contribuir com o sistema.

O LG K11 Plus representa atualmente esse modelo.

```text
                         CLUSTER REPLICADO

                    Galaxy A15
                      PRIMARY
                         |
                         | WAL
                         v
                     Motorola
                    HOT STANDBY


                    PROCESSAMENTO
                       AUXILIAR

                     LG K11 Plus
                    ARMHF / 32-bit
                         |
                         +-- workers
                         +-- processamento
                         +-- tarefas em lote
                         +-- PostgreSQL local
                             quando necessário
```

Essa separação permite explorar dispositivos com características diferentes sem obrigar todos eles a participar do mesmo mecanismo de replicação.

---

# Escalabilidade experimental

Uma evolução futura poderá adicionar outros dispositivos compatíveis.

Por exemplo:

```text
                         PRIMARY
                       Galaxy A15
                           |
              +------------+------------+
              |                         |
              v                         v
          STANDBY 1                 STANDBY 2
          Motorola                  ARM64 futuro
              |                         |
              +-----------+-------------+
                          |
                          v
                    capacidade de
                    leitura adicional
```

Esse cenário ainda não foi testado.

Antes de aumentar o número de standbys será necessário avaliar o custo adicional no primary, principalmente:

```text
WAL senders
rede Wi-Fi
CPU
I/O
retenção de WAL
consumo de energia
temperatura
```

---

# Objetivo do experimento

O objetivo deste trabalho não é afirmar que smartphones substituem servidores convencionais.

O objetivo é investigar, através de dispositivos reais, até onde uma infraestrutura PostgreSQL pode ser construída sobre:

```text
Android
kernel Linux compartilhado
root
Ubuntu chroot
ARM
PostgreSQL compilado do código-fonte
memória compartilhada adaptada
rede local
streaming replication
```

O interesse está tanto nos resultados positivos quanto nas limitações encontradas.

Uma falha reproduzível ou uma abordagem descartada também constitui informação útil para compreender os limites da arquitetura.

---

# Conclusão

Os experimentos realizados demonstraram streaming replication físico funcional entre duas instalações PostgreSQL 18.6 executadas em smartphones Android ARM64 através de Ubuntu 24.04 chroot.

O Galaxy A15 opera como primary e o Motorola Android One como hot standby.

Durante a validação, o Galaxy A15 apresentou o Motorola em:

```text
state      = streaming
sync_state = async
```

e o Motorola apresentou:

```text
pg_is_in_recovery() = true
transaction_read_only = on
```

O WAL receiver do Motorola confirmou conexão com:

```text
192.168.1.50:5432
```

e um teste real demonstrou que uma tabela e uma linha criadas no Galaxy A15 tornaram-se disponíveis para consulta no Motorola.

Uma tentativa de escrita direta no hot standby foi corretamente recusada pelo PostgreSQL.

Portanto, o resultado atual vai além de simplesmente executar PostgreSQL isoladamente em Android:

```text
Android + Ubuntu chroot + PostgreSQL
                    |
                    v
       dois dispositivos ARM64
                    |
                    v
      physical streaming replication
                    |
                    v
        PRIMARY + HOT STANDBY
```

Isso fornece uma base concreta para os próximos experimentos envolvendo carga concorrente, distribuição de leitura, recuperação de falhas e comportamento de um cluster PostgreSQL construído com dispositivos Android.

O projeto continuará distinguindo claramente aquilo que foi comprovado em dispositivos reais daquilo que permanece como hipótese ou experimento futuro.
