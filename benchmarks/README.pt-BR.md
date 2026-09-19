# Benchmarks do PostgreSQL 18.6 em Android

[English version](README.md)

## Visão geral

Este documento apresenta benchmarks experimentais do PostgreSQL 18.6 executado em dispositivos Android com root, utilizando Ubuntu 24.04 em chroot.

Os testes fazem parte do projeto `postgresql-android-chroot` e têm como objetivo avaliar, em hardware Android real, o comportamento do PostgreSQL em cenários de ingestão remota de grandes volumes de dados e replicação física por streaming.

Os resultados apresentados aqui correspondem às execuções efetivamente realizadas no ambiente de testes descrito neste documento. Eles não devem ser interpretados como benchmarks universais do PostgreSQL, do Android ou dos dispositivos utilizados.

## Objetivos

Os benchmarks foram realizados para avaliar:

- ingestão remota utilizando `COPY FROM STDIN`;
- comportamento com 100 mil, 1 milhão, 10 milhões e 20 milhões de registros;
- diferenças observadas entre diferentes dispositivos atuando como clientes;
- comportamento do PostgreSQL no Samsung Galaxy A15 como servidor primário;
- impacto observado durante execuções com replicação física ativa;
- avanço da posição WAL durante as cargas;
- atividade de checkpoints durante cargas maiores;
- capacidade do Motorola de recuperar atraso de replicação;
- comportamento da retenção de WAL durante interrupções do standby;
- viabilidade prática de utilizar dispositivos Android como nós PostgreSQL.

## Arquitetura do ambiente

O Samsung Galaxy A15 foi utilizado como servidor PostgreSQL primário.

O Motorola Android One XT1941-3 foi utilizado em dois papéis diferentes:

1. cliente remoto durante os benchmarks sem replicação;
2. standby físico ARM64 durante os benchmarks com replicação ativa.

O LG K11 Plus foi utilizado como cliente remoto ARMHF/32-bit.

Um computador Ubuntu Desktop foi utilizado como cliente de referência para as cargas remotas.

A arquitetura lógica dos testes foi:

```text
Sem replicação:

Ubuntu Desktop ───────┐
                      │
Motorola ─────────────┼── COPY FROM STDIN ──> Samsung Galaxy A15
                      │                       PostgreSQL 18.6
LG K11 Plus ──────────┘


Com replicação:

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

## PostgreSQL utilizado

O servidor primário e o standby utilizavam PostgreSQL 18.6 compilado a partir do código-fonte.

Prefixo de instalação:

/usr/local/pgsql18

Diretório de dados:

/usr/local/pgsql18/data

Nos dispositivos Android, o PostgreSQL era executado dentro de Ubuntu 24.04 em chroot compartilhando o kernel Android.

A biblioteca de compatibilidade android-shmem era carregada através de:

LD_PRELOAD=/usr/local/lib/libandroid-shmem.so

Para memória compartilhada dinâmica foi utilizado:

dynamic_shared_memory_type = mmap


## Tabela utilizada no benchmark

As cargas utilizaram uma tabela sem chave primária e sem índices adicionais, permitindo avaliar a ingestão sequencial por COPY sem o custo de manutenção de índices.

CREATE TABLE benchmark_copy
(
    id bigint NOT NULL,
    origem text NOT NULL,
    numero_processo varchar(30) NOT NULL,
    nome text NOT NULL,
    texto text NOT NULL,
    criado_em timestamptz NOT NULL DEFAULT now()
);

Antes de cada execução válida, a tabela era esvaziada com:

TRUNCATE TABLE benchmark_copy;

## Geração e transmissão dos registros

Os registros eram gerados no próprio cliente utilizando awk e enviados diretamente ao psql através de pipe.

Exemplo simplificado:

awk '...' |
psql \
    -h PRIMARY_IP \
    -p 5432 \
    -U postgres \
    -d postgres \
    -c "COPY benchmark_copy
        (id, origem, numero_processo, nome, texto)
        FROM STDIN;"

Não era criado arquivo CSV intermediário.

Consequentemente, os registros eram produzidos e transmitidos como fluxo:

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

## Interpretação do tempo medido

O tempo das cargas foi coletado com GNU time.

Exemplo:

real
user
sys
cpu
max_rss_kb

O valor real representa o tempo observado pelo cliente para o pipeline completo.

Portanto, os números apresentados neste documento são benchmarks end-to-end.

Eles incluem, entre outros fatores:

geração dos registros pelo awk;
processamento do psql;
transmissão pela rede;
processamento do protocolo PostgreSQL;
execução do COPY;
geração de WAL;
atividade de armazenamento;
checkpoints que ocorram durante o intervalo;
commit da transação;
e, quando habilitada, atividade associada à replicação.

Por esse motivo, diferenças entre execuções com e sem replicação não devem ser interpretadas automaticamente como o custo isolado da replicação.

## Memória do cliente

Como os registros eram gerados e enviados continuamente através de pipe, o cliente não precisava manter todo o conjunto de dados em memória.

Isso explica os valores relativamente pequenos de max_rss_kb observados mesmo em cargas de 10 e 20 milhões de registros.

## WAL

O avanço de WAL foi calculado utilizando posições LSN observadas antes e depois das cargas.

Exemplo:

SELECT pg_wal_lsn_diff(
    pg_current_wal_lsn(),
    'LSN_INICIAL'
);

Esse valor deve ser interpretado como:

avanço da posição WAL do cluster durante o intervalo do benchmark.

Ele não representa necessariamente a quantidade exata de WAL produzida exclusivamente pela tabela benchmark_copy.

Outras atividades do cluster que ocorram dentro do mesmo intervalo também podem contribuir para o avanço da posição WAL.

## Validação dos registros

Após as cargas maiores, foram realizadas verificações como:

SELECT
    count(*) AS registros,
    min(id) AS menor_id,
    max(id) AS maior_id,
    count(DISTINCT id) AS ids_distintos
FROM benchmark_copy;

Também foi utilizado pg_stat_database.tup_inserted como uma verificação adicional da quantidade de tuplas inseridas no banco postgres durante o intervalo observado.

Nos testes com replicação, os registros também foram consultados diretamente no standby Motorola.

## Checkpoints

No PostgreSQL 18, a atividade de checkpoints foi acompanhada através de:

SELECT
    num_timed,
    num_requested,
    num_done,
    write_time,
    sync_time,
    buffers_written
FROM pg_stat_checkpointer;

Foram coletadas fotografias antes e depois das cargas maiores para permitir a comparação das diferenças observadas durante cada execução.

As próximas seções apresentam os resultados experimentais obtidos com cada cliente e posteriormente os testes realizados com replicação física ativa.

# Resultados sem replicação

Nesta primeira série, o PostgreSQL do Samsung Galaxy A15 recebeu as cargas sem um standby conectado.

A consulta a `pg_stat_replication` retornava zero conexões durante os testes válidos desta série.

Foram utilizados três clientes:

- Ubuntu Desktop;
- Motorola Android One XT1941-3;
- LG K11 Plus.

Cada cliente executou cargas de:

```text
100.000
1.000.000
10.000.000
20.000.000
```

## Throughput consolidado

A tabela abaixo apresenta o throughput end-to-end calculado a partir do tempo real observado em cada cliente.

| Registros | Desktop → A15 | Motorola → A15 | LG K11 Plus → A15 |
|---:|---:|---:|---:|
| 100.000 | ~156.250 reg/s | ~59.172 reg/s | ~36.496 reg/s |
| 1.000.000 | ~225.225 reg/s | ~82.508 reg/s | ~63.012 reg/s |
| 10.000.000 | ~231.160 reg/s | ~85.521 reg/s | ~64.902 reg/s |
| 20.000.000 | ~266.382 reg/s | ~85.455 reg/s | ~64.070 reg/s |

Esses valores representam o pipeline completo do cliente até o término do COPY no A15.

Não devem ser interpretados isoladamente como capacidade máxima do servidor PostgreSQL.

## Ubuntu Desktop → A15

O Ubuntu Desktop apresentou os maiores throughputs entre os três clientes utilizados.

### 100 mil registros
COPY                 = 100.000
real                 = 0,64 s
user                 = 0,20 s
sys                  = 0,05 s
cpu                  = 40%
max_rss_kb           = 4.152 KB
throughput           ≈ 156.250 reg/s
tamanho da tabela    = 14.983.168 bytes
avanço WAL           = 13.040.968 bytes

### 1 milhão de registros
COPY                 = 1.000.000
real                 = 4,44 s
user                 = 1,73 s
sys                  = 0,35 s
cpu                  = 47%
max_rss_kb           = 4.060 KB
throughput           ≈ 225.225 reg/s
tamanho da tabela    = 149.233.664 bytes
avanço WAL           = 130.742.192 bytes

### 10 milhões de registros

COPY                 = 10.000.000
real                 = 43,26 s
user                 = 17,17 s
sys                  = 3,62 s
cpu                  = 48%
max_rss_kb           = 4.120 KB
throughput           ≈ 231.160 reg/s
tamanho da tabela    = 1.490.173.952 bytes
avanço WAL           = 2.904.125.440 bytes

### 20 milhões de registros

COPY                 = 20.000.000
real                 = 75,08 s
user                 = 34,07 s
sys                  = 7,05 s
cpu                  = 54%
max_rss_kb           = 4.064 KB
throughput           ≈ 266.382 reg/s
tamanho da tabela    = 2.980.044.800 bytes
avanço WAL           = 5.806.284.456 bytes

Para a execução de 20 milhões, pg_stat_database.tup_inserted avançou exatamente 20.000.000.

A atividade observada no pg_stat_checkpointer durante essa execução foi:

num_requested   +11
num_done        +10
write_time      +139.900 ms
sync_time       +633 ms
buffers_written +7.717

## Motorola XT1941-3 → A15

O Motorola utilizou seu PostgreSQL local parado durante esta série para impedir que a replicação física se conectasse automaticamente ao A15.

O psql 18.6 do próprio ambiente ARM64 foi utilizado como cliente.

### 100 mil registros

COPY                 = 100.000
real                 = 1,69 s
user                 = 0,68 s
sys                  = 0,32 s
cpu                  = 59%
max_rss_kb           = 4.228 KB
throughput           ≈ 59.172 reg/s
tamanho da tabela    = 14.983.168 bytes

O intervalo de observação dessa execução apresentou:

avanço WAL = 39.422.728 bytes

Entretanto, pg_stat_database.tup_inserted avançou 300.000 nesse intervalo, embora o COPY tivesse inserido somente 100.000 registros.

Isso indica atividade adicional no banco durante as fotografias utilizadas para essa medição.

Por esse motivo, o valor de avanço WAL dessa execução não deve ser tratado como uma medição limpa associada somente ao benchmark de 100 mil registros.

### 1 milhão de registros

COPY                 = 1.000.000
real                 = 12,12 s
user                 = 6,32 s
sys                  = 2,82 s
cpu                  = 75%
max_rss_kb           = 4.228 KB
throughput           ≈ 82.508 reg/s
tamanho da tabela    = 149.233.664 bytes
avanço WAL           = 130.823.360 bytes
tup_inserted         = +1.000.000

### 10 milhões de registros

COPY                 = 10.000.000
real                 = 116,93 s
user                 = 64,18 s
sys                  = 28,51 s
cpu                  = 79%
max_rss_kb           = 4.228 KB
throughput           ≈ 85.521 reg/s
tamanho da tabela    = 1.490.198.528 bytes
avanço WAL           = 2.826.203.760 bytes
tup_inserted         = +10.000.000

Atividade do checkpointer observada:

num_requested   +5
num_done        +5
write_time      +247.256 ms
sync_time       +373 ms
buffers_written +2.228

### 20 milhões de registros

COPY                 = 20.000.000
real                 = 234,04 s
user                 = 128,05 s
sys                  = 56,81 s
cpu                  = 78%
max_rss_kb           = 4.228 KB
throughput           ≈ 85.455 reg/s
tamanho da tabela    = 3.066.126.336 bytes
avanço WAL           = 5.843.122.744 bytes
tup_inserted         = +20.000.000

Atividade do checkpointer observada:

num_timed       +2
num_requested   +11
num_done        +12
write_time      +564.656 ms
sync_time       +846 ms
buffers_written +2.137

Nas cargas de 10 e 20 milhões, o throughput do pipeline Motorola → A15 permaneceu próximo de 85 mil registros por segundo.

Esse resultado não identifica isoladamente o componente limitante. O pipeline envolve geração com awk, CPU do cliente, psql, rede, processamento do servidor, WAL e armazenamento.

## LG K11 Plus → A15

O LG K11 Plus executava Ubuntu 24.04 ARMHF em chroot e utilizava psql 18.6 de 32 bits.

Assim como no Motorola, o PostgreSQL local foi mantido parado durante os testes.

### 100 mil registros

COPY                 = 100.000
real                 = 2,74 s
user                 = 1,06 s
sys                  = 0,21 s
cpu                  = 46%
max_rss_kb           = 2.840 KB
throughput           ≈ 36.496 reg/s
tamanho da tabela    = 14.983.168 bytes
avanço WAL           = 13.115.048 bytes
tup_inserted         = +100.000

### 1 milhão de registros

COPY                 = 1.000.000
real                 = 15,87 s
user                 = 9,28 s
sys                  = 1,84 s
cpu                  = 70%
max_rss_kb           = 2.840 KB
throughput           ≈ 63.012 reg/s
tamanho da tabela    = 149.233.664 bytes
avanço WAL           = 130.820.992 bytes
tup_inserted         = +1.000.000

### 10 milhões de registros

COPY                 = 10.000.000
real                 = 154,08 s
user                 = 94,13 s
sys                  = 19,12 s
cpu                  = 73%
max_rss_kb           = 2.840 KB
throughput           ≈ 64.902 reg/s
tamanho da tabela    = 1.490.173.952 bytes
avanço WAL           = 2.903.298.504 bytes
tup_inserted         = +10.000.000

Atividade do checkpointer observada:

num_timed       +1
num_requested   +5
num_done        +5
write_time      +163.633 ms
sync_time       +286 ms
buffers_written +3.610

### 20 milhões de registros

COPY                 = 20.000.000
real                 = 312,16 s
user                 = 190,06 s
sys                  = 37,33 s
cpu                  = 72%
max_rss_kb           = 2.840 KB
throughput           ≈ 64.070 reg/s
tamanho da tabela    = 3.066.068.992 bytes
avanço WAL           = 5.955.429.672 bytes
tup_inserted         = +20.000.000

Atividade do checkpointer observada:

num_requested   +11
num_done        +11
write_time      +436.912 ms
sync_time       +788 ms
buffers_written +12.768

## Comparação dos clientes

As execuções maiores mostraram comportamentos relativamente estáveis para os dois clientes Android.

Em 10 milhões:

Desktop      ≈ 231.160 reg/s
Motorola     ≈  85.521 reg/s
LG K11 Plus  ≈  64.902 reg/s

Em 20 milhões:

Desktop      ≈ 266.382 reg/s
Motorola     ≈  85.455 reg/s
LG K11 Plus  ≈  64.070 reg/s

Esses números demonstram diferenças no desempenho end-to-end dos três pipelines testados.

Eles não permitem, isoladamente, concluir se a diferença é causada principalmente por CPU, geração dos dados, rede, arquitetura ARM64/ARMHF, sistema Android, armazenamento ou outro componente.

## Observação sobre o campo origem

O conteúdo utilizado no campo origem não possuía exatamente o mesmo comprimento nos três clientes:

Desktop    = 7 caracteres
Motorola   = 8 caracteres
LGK11Plus  = 9 caracteres

Essa diferença altera ligeiramente o volume de dados armazenado por registro e deve ser considerada ao comparar tamanhos físicos das tabelas entre clientes.

A próxima série utiliza o Ubuntu Desktop como cliente e mantém a replicação física A15 → Motorola ativa durante as cargas.

# Benchmarks com replicação física ativa

Nesta série, o Ubuntu Desktop continuou sendo o cliente responsável pela geração e transmissão dos registros ao Samsung Galaxy A15.

A diferença foi a presença do Motorola XT1941-3 como standby físico ativo:

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

A replicação utilizada era assíncrona:

state      = streaming
sync_state = async

Portanto, o commit no primary não aguardava confirmação síncrona do standby.

Antes das execuções consideradas válidas, foram verificadas as posições WAL do primary e do standby.

Após as cargas, também foram verificadas:

- quantidade de registros no A15;
- intervalo e unicidade dos IDs;
- avanço da posição WAL;
- `tup_inserted`;
- atividade do checkpointer;
- estado de `pg_stat_replication`;
- quantidade de registros disponível no Motorola;
- posições receive/replay do standby;
- retorno posterior da replicação para lag zero.

## Resultado consolidado

Os resultados oficiais comparáveis obtidos com e sem o standby ativo foram:

| Registros | Sem réplica | Com réplica | Throughput sem réplica | Throughput com réplica |
|---:|---:|---:|---:|---:|
| 1.000.000 | 4,44 s | 5,80 s | ~225.225 reg/s | ~172.414 reg/s |
| 10.000.000 | 43,26 s | 62,78 s | ~231.160 reg/s | ~159.286 reg/s |
| 20.000.000 | 75,08 s | 128,29 s | ~266.382 reg/s | ~155.897 reg/s |

Essas diferenças são diferenças observadas entre execuções end-to-end.

Elas não representam uma medição isolada do custo interno da replicação.

## 1 milhão de registros

A execução válida de 1 milhão foi realizada com o Desktop utilizando Ethernet e com o Motorola conectado ao A15 como standby.

Resultado do cliente:

COPY                 = 1.000.000
real                 = 5,80 s
user                 = 2,03 s
sys                  = 0,31 s
cpu                  = 40%
max_rss_kb           = 4.148 KB
throughput           ≈ 172.414 reg/s

O avanço observado da posição WAL foi:

130.726.376 bytes

O tamanho da tabela foi:

149.233.664 bytes

`pg_stat_database.tup_inserted` avançou exatamente:

+1.000.000

Ao final da verificação, as posições de replicação estavam sincronizadas e o atraso em bytes era zero.

O Motorola também apresentou:

1.000.000 registros
IDs de 1 até 1.000.000
1.000.000 IDs distintos

Comparando apenas as duas execuções observadas:

sem réplica = 4,44 s
com réplica = 5,80 s

Diferença de tempo:

+1,36 s
aproximadamente +30,6%

A redução calculada do throughput foi de aproximadamente 23,5%.

Esses percentuais descrevem somente essas execuções e não devem ser generalizados como overhead fixo da replicação PostgreSQL.

## Primeira tentativa de 10 milhões: execução descartada

Antes da configuração de uma janela maior de retenção WAL, foi realizada uma tentativa de 10 milhões de registros com o Motorola configurado como standby.

O cliente concluiu:

COPY                 = 10.000.000
real                 = 52,05 s
user                 = 19,94 s
sys                  = 3,40 s
cpu                  = 44%
max_rss_kb           = 4.048 KB
throughput           ≈ 192.123 reg/s

No A15, a carga propriamente dita estava íntegra:

registros             = 10.000.000
IDs                    = 1 até 10.000.000
IDs distintos          = 10.000.000
tup_inserted           = +10.000.000

Entretanto, ao verificar a replicação após a carga:

pg_stat_replication = 0 rows

No Motorola:

pg_stat_wal_receiver = 0 rows
benchmark_copy        = 0 registros

O log do standby apresentou repetidamente uma mensagem equivalente a:

requested WAL segment ... has already been removed

O standby havia perdido a continuidade necessária para prosseguir com o streaming.

Essa execução foi, portanto, descartada da comparação oficial de desempenho com replicação ativa.

O valor de 52,05 segundos permanece documentado como parte do experimento de falha, mas não é utilizado como resultado oficial da série com replicação íntegra.

### Condição que permitiu a perda do WAL necessário

Naquele momento, o primary utilizava:

wal_keep_size = 0

e não havia replication slot protegendo o WAL necessário pelo standby.

Durante a geração intensa de WAL, uma interrupção na continuidade do standby permitiu que segmentos antigos de que ele ainda precisava fossem reciclados pelo primary.

Quando o Motorola tentou continuar o streaming, o segmento solicitado já não estava disponível.

A recuperação exigiu uma nova cópia física utilizando `pg_basebackup`.

## Introdução de wal_keep_size = 8GB

Depois da falha experimental, o A15 foi configurado com:

wal_keep_size = 8GB

A configuração foi aplicada através de `ALTER SYSTEM` e o PostgreSQL foi reiniciado.

O objetivo dessa configuração no experimento era manter uma janela mínima de WAL antigo suficientemente grande para permitir que o Motorola recuperasse atrasos temporários durante cargas intensas.

Esse valor foi escolhido para o ambiente experimental.

Ele não deve ser interpretado como recomendação universal para outras instalações.

Também é importante distinguir:

wal_keep_size = 8GB
max_wal_size  = 1GB
min_wal_size  = 80MB

Essas configurações possuem finalidades diferentes.

`max_wal_size` participa do controle relacionado à frequência de checkpoints e não funciona como um limite rígido que impeça `pg_wal` de ultrapassar esse tamanho.

`wal_keep_size`, por sua vez, influencia a quantidade mínima de WAL antigo mantida para permitir recuperação de standbys atrasados.

## Segunda execução de 10 milhões: válida

Após a reconstrução do Motorola e a configuração de `wal_keep_size = 8GB`, o teste de 10 milhões foi repetido.

Antes da carga:

- A15 e Motorola estavam em streaming;
- a tabela estava vazia;
- o standby estava sincronizado;
- `wal_keep_size` estava configurado em 8GB.

Resultado do cliente:

COPY                 = 10.000.000
real                 = 62,78 s
user                 = 21,29 s
sys                  = 3,46 s
cpu                  = 39%
max_rss_kb           = 4.096 KB
throughput           ≈ 159.286 reg/s

No A15:

registros             = 10.000.000
menor_id              = 1
maior_id              = 10.000.000
ids_distintos         = 10.000.000
tup_inserted          = +10.000.000
tamanho da tabela     = 1.490.182.144 bytes
avanço WAL            = 2.963.995.672 bytes

Atividade observada no checkpointer:

num_requested   +5
num_done        +4
write_time      +108.871 ms
sync_time       +128 ms
buffers_written +1.579

Durante a verificação imediatamente posterior à carga, o Motorola continuava conectado em estado:

streaming / async

O standby estava atrasado e ainda recebendo WAL.

Posteriormente, a consulta realizada diretamente no Motorola confirmou:

registros       = 10.000.000
menor_id        = 1
maior_id        = 10.000.000
ids_distintos   = 10.000.000

Após o catch-up, o A15 apresentou:

primary_lsn = B/E4AD7B40
sent_lsn    = B/E4AD7B40
write_lsn   = B/E4AD7B40
flush_lsn   = B/E4AD7B40
replay_lsn  = B/E4AD7B40

primary_replay_lag_bytes = 0
sent_replay_lag_bytes    = 0

A réplica recuperou completamente o atraso sem necessidade de novo `pg_basebackup`.

### Comparação da execução de 10 milhões

Sem replicação:

real       = 43,26 s
throughput ≈ 231.160 reg/s

Com replicação ativa e íntegra:

real       = 62,78 s
throughput ≈ 159.286 reg/s

Diferença observada:

tempo      = +19,52 s
tempo (%)  ≈ +45,1%
throughput ≈ -31,1%

Novamente, esses valores descrevem o pipeline end-to-end das duas execuções e não isolam o custo da replicação.

## Execução de 20 milhões com replicação

A execução de 20 milhões foi realizada mantendo:

wal_keep_size = 8GB

Antes da carga, o Motorola apresentava:

registros   = 0
status      = streaming
receive_lsn = replay_lsn

Resultado do Desktop:

COPY                 = 20.000.000
real                 = 128,29 s
user                 = 43,44 s
sys                  = 7,46 s
cpu                  = 39%
max_rss_kb           = 3.976 KB
throughput           ≈ 155.897 reg/s

No A15:

registros             = 20.000.000
menor_id              = 1
maior_id              = 20.000.000
ids_distintos         = 20.000.000
tup_inserted          = +20.000.000
tamanho da tabela     = 2.980.126.720 bytes
avanço WAL            = 5.865.908.800 bytes

O avanço observado corresponde a aproximadamente 5,46 GiB.

### Atividade do checkpointer

Durante a execução de 20 milhões foram observadas as seguintes diferenças:

num_timed       0
num_requested   +11
num_done        +10
write_time      +267.630 ms
sync_time       +574 ms
buffers_written +6.331

### Atraso do standby durante 20 milhões

Na fotografia realizada após a carga, o Motorola ainda permanecia conectado:

state      = streaming
sync_state = async

As posições observadas eram:

primary_lsn = D/4251D080
sent_lsn    = C/85052000
write_lsn   = C/84C32000
flush_lsn   = C/84C32000
replay_lsn  = C/84C30468

A distância calculada entre a posição atual do primary e o replay do standby naquele instante foi:

3.180.252.184 bytes

Isso corresponde a aproximadamente 2,96 GiB de atraso em relação ao primary naquela fotografia.

Já a diferença entre o WAL que havia sido enviado e o que havia sido reproduzido era:

4.332.440 bytes

Portanto, naquele instante, grande parte da distância até o primary ainda estava relacionada ao avanço do envio do WAL, e não somente a uma grande fila já recebida aguardando replay.

### Disponibilidade dos 20 milhões no standby

Durante o processo de catch-up, uma consulta diretamente no Motorola confirmou:

em_recovery    = true
status         = streaming
registros      = 20.000.000
menor_id       = 1
maior_id       = 20.000.000
ids_distintos  = 20.000.000

Isso demonstra que o standby já havia reproduzido o commit necessário para tornar os 20 milhões de registros visíveis para consultas, embora ainda estivesse processando WAL posterior.

Posteriormente, o A15 confirmou a recuperação completa:

primary_lsn = D/42526540
sent_lsn    = D/42526540
write_lsn   = D/42526540
flush_lsn   = D/42526540
replay_lsn  = D/42526540

primary_replay_lag_bytes = 0
sent_replay_lag_bytes    = 0

O Motorola retornou, portanto, a lag zero sem reconstrução da réplica.

### Comparação da execução de 20 milhões

Sem replicação:

real       = 75,08 s
throughput ≈ 266.382 reg/s

Com replicação ativa:

real       = 128,29 s
throughput ≈ 155.897 reg/s

Diferença observada:

tempo      = +53,21 s
tempo (%)  ≈ +70,9%
throughput ≈ -41,5%

Essas diferenças não devem ser apresentadas como overhead fixo da replicação PostgreSQL.

## Estado final do WAL

Depois da conclusão dos benchmarks e do catch-up completo do Motorola, o A15 apresentava:

wal_keep_size = 8GB
max_wal_size  = 1GB
min_wal_size  = 80MB

O diretório:

/usr/local/pgsql18/data/pg_wal

ocupava aproximadamente:

8,6G

O filesystem do A15 apresentava:

225G total
87G utilizados
139G disponíveis
39% utilizado

A replicação terminou no estado:

state      = streaming
sync_state = async
lag        = 0 bytes

com primary e standby na mesma posição WAL.

## Resultado experimental da retenção de WAL

Os testes produziram duas situações distintas no mesmo ambiente.

Antes:

wal_keep_size = 0
standby perdeu continuidade
WAL necessário foi removido
replicação não conseguiu continuar
novo pg_basebackup foi necessário

Depois:

wal_keep_size = 8GB
carga de 10 milhões concluída
carga de 20 milhões concluída
avanço de aproximadamente 5,46 GiB de WAL na carga de 20 milhões
standby chegou a ficar aproximadamente 2,96 GiB atrás
standby permaneceu em streaming
20 milhões tornaram-se consultáveis no standby
standby realizou catch-up
lag final = 0
nenhum novo pg_basebackup foi necessário

Esse resultado demonstra o comportamento observado especificamente neste ambiente experimental.

Ele não estabelece que 8GB seja o valor adequado para todos os sistemas.

A retenção necessária depende, entre outros fatores, da taxa de geração de WAL, duração possível de interrupções do standby, espaço disponível e estratégia de replicação adotada.

# Conclusões experimentais

Os benchmarks demonstraram que foi possível executar cargas remotas de até 20 milhões de registros em uma única operação `COPY FROM STDIN` para PostgreSQL 18.6 executado no Samsung Galaxy A15 dentro de Ubuntu 24.04 em chroot.

Nas execuções realizadas, o A15 recebeu corretamente as cargas originadas de três tipos diferentes de cliente:

- Ubuntu Desktop;
- Android ARM64;
- Android ARMHF/32-bit.

O maior teste realizado inseriu 20 milhões de registros em uma única operação `COPY`.

Sem replicação, o Ubuntu Desktop concluiu essa carga em:

75,08 segundos

Com o Motorola operando como standby físico, a execução comparável foi concluída em:

128,29 segundos

Em ambos os casos, os 20 milhões de registros foram validados no primary.

Na execução com replicação, os mesmos 20 milhões também foram posteriormente validados no standby.

## PostgreSQL no Android como servidor

Os resultados demonstram que, no ambiente testado, o PostgreSQL 18.6 compilado para ARM64 foi capaz de operar no Samsung Galaxy A15 como servidor de banco de dados e receber cargas remotas de grande volume.

Os benchmarks não estabelecem equivalência entre um smartphone e hardware de servidor convencional.

Eles demonstram a funcionalidade e o desempenho observados neste hardware e nesta configuração específicos.

## Dispositivos Android como clientes

Motorola e LG K11 Plus conseguiram gerar e transmitir milhões de registros diretamente para o A15 através de `COPY FROM STDIN`.

Nas cargas maiores, o throughput observado estabilizou aproximadamente em:

Motorola ARM64    ≈ 85 mil registros/s
LG K11 Plus ARMHF ≈ 64 mil registros/s

O Ubuntu Desktop apresentou throughput significativamente maior no mesmo tipo de pipeline.

O benchmark não isolou qual componente explica essa diferença.

## Replicação física entre dispositivos Android

A replicação física PostgreSQL 18.6 entre o A15 e o Motorola permaneceu funcional durante as execuções válidas de:

1 milhão
10 milhões
20 milhões

Após as cargas, o standby conseguiu alcançar novamente a mesma posição WAL do primary.

Na execução de 20 milhões, foi observado temporariamente um atraso de aproximadamente:

3.180.252.184 bytes

entre a posição atual do primary e a posição reproduzida pelo standby.

Mesmo assim, o Motorola permaneceu em streaming, tornou os 20 milhões de registros disponíveis para consultas e posteriormente retornou a lag zero.

## Retenção de WAL

O experimento também demonstrou uma situação real de perda da continuidade da replicação.

Com:

wal_keep_size = 0

e sem replication slot, uma interrupção do standby durante geração intensa de WAL permitiu que segmentos ainda necessários fossem removidos.

A reconstrução do standby com `pg_basebackup` foi necessária.

Após configurar:

wal_keep_size = 8GB

as execuções posteriores de 10 e 20 milhões permitiram que o Motorola recuperasse atrasos sem nova reconstrução.

Na execução de 20 milhões, a posição WAL avançou aproximadamente 5,46 GiB durante o intervalo medido.

O resultado é específico deste experimento e não define 8GB como configuração recomendada para outros ambientes.

## Replicação assíncrona

Todos os benchmarks de replicação descritos neste documento utilizaram:

sync_state = async

Consequentemente, o commit no A15 não dependia de confirmação síncrona do Motorola.

Por isso, a diferença de tempo entre os benchmarks com e sem standby não deve ser interpretada como tempo de espera direto pelo replay da réplica.

A execução envolve diversos componentes que não foram isolados individualmente.

# Limitações do benchmark

Este projeto procura preservar os resultados brutos e também suas limitações.

Entre as principais limitações estão:

- os testes não foram executados em laboratório com rede totalmente isolada;
- os dispositivos possuem hardware e arquiteturas diferentes;
- Desktop, Motorola e LG possuem capacidades de CPU diferentes;
- os caminhos de rede não são necessariamente equivalentes;
- o tempo inclui geração dos registros no cliente;
- o tempo inclui transmissão TCP/IP;
- o tempo inclui processamento do `psql`;
- o tempo inclui processamento do servidor;
- checkpoints podem ocorrer durante as execuções;
- outras atividades do cluster podem contribuir para o avanço WAL;
- o benchmark não mede separadamente CPU, rede e armazenamento;
- o campo `origem` possui comprimentos diferentes entre os três clientes;
- não foram executadas múltiplas repetições estatísticas de cada combinação;
- os resultados representam as execuções observadas e não uma distribuição estatística de desempenho.

## CPU apresentada pelo GNU time

O campo `cpu` apresentado nos resultados pertence ao processo/pipeline executado no cliente.

Ele não representa diretamente a utilização de CPU do Samsung Galaxy A15.

Por exemplo:

cpu = 39%

em uma execução realizada no Ubuntu Desktop descreve a utilização observada pelo processo medido no Desktop.

Não significa que o PostgreSQL do A15 utilizou 39% de CPU.

## Avanço WAL

Os valores denominados `avanço WAL` correspondem à diferença entre posições LSN observadas durante o intervalo do benchmark.

Como o WAL pertence ao cluster PostgreSQL, esses valores não devem ser interpretados como quantidade de WAL produzida exclusivamente pelos registros de `benchmark_copy`.

## Comparações de desempenho

Os percentuais apresentados entre execuções com e sem replicação são comparações descritivas dos resultados observados.

Por exemplo, a diferença entre:

43,26 s sem réplica

e:

62,78 s com réplica

não demonstra que a replicação física adiciona universalmente 45,1% ao tempo de uma operação `COPY`.

Para determinar o custo isolado da replicação seriam necessários experimentos adicionais, repetidos e controlados, com instrumentação específica para separar os diferentes componentes do pipeline.

# Reprodutibilidade

A metodologia foi mantida deliberadamente simples.

Os registros eram gerados sequencialmente no cliente e enviados ao PostgreSQL através de pipe, sem arquivo intermediário.

A estrutura geral utilizada foi:

awk → pipe → psql → TCP/IP → COPY FROM STDIN → PostgreSQL

As cargas utilizadas foram:

100.000
1.000.000
10.000.000
20.000.000

A tabela era esvaziada antes de cada execução válida.

As cargas maiores eram posteriormente verificadas através de contagem, menor ID, maior ID e quantidade de IDs distintos.

Nos testes com replicação, também eram verificadas as posições:

sent_lsn
write_lsn
flush_lsn
replay_lsn

O estado final esperado para uma execução considerada recuperada era:

state = streaming

e:

primary_lsn = sent_lsn = write_lsn = flush_lsn = replay_lsn

com:

replay lag = 0 bytes

# Escopo dos resultados

Os números publicados neste documento devem ser entendidos como resultados experimentais reproduzíveis dentro de uma arquitetura específica, e não como especificações oficiais de desempenho dos dispositivos utilizados.

O objetivo principal é registrar o que foi possível executar com PostgreSQL 18.6 em dispositivos Android reais e fornecer dados concretos para que outros usuários possam comparar seus próprios experimentos.

Melhorias futuras podem incluir:

- múltiplas repetições de cada benchmark;
- média, mediana e desvio padrão;
- medição simultânea de CPU do servidor;
- utilização de memória do servidor;
- throughput de rede;
- latência de rede;
- I/O e latência do armazenamento;
- taxa instantânea de geração de WAL;
- tempo necessário para o standby realizar catch-up;
- comparação com replication slots;
- comparação entre diferentes valores de `wal_keep_size`;
- benchmarks de leitura no hot standby;
- consultas concorrentes no primary e no standby.
