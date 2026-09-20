# PostgreSQL 18 em Android com Root e Ubuntu 24.04 Chroot

[English](README.md)

## Visão geral

Este projeto documenta um experimento prático executando PostgreSQL 18.6, compilado a partir do código-fonte, dentro de ambientes Ubuntu 24.04 chroot em dispositivos Android com acesso root.

O projeto começou como uma investigação para verificar se smartphones Android poderiam ser utilizados como nós reais PostgreSQL para processamento de dados, armazenamento, replicação e cargas de consulta.

O resultado é um pequeno cluster PostgreSQL funcional utilizando smartphones Android.

A arquitetura atualmente testada inclui:

- Samsung Galaxy A15 como servidor PostgreSQL principal (primary)
- Motorola Android One (deen) como hot standby/réplica de leitura PostgreSQL ARM64
- LG K11 Plus como nó experimental PostgreSQL e de processamento ARMHF/32 bits
- Ubuntu 24.04 executado em ambientes chroot sobre Android
- PostgreSQL 18.6 compilado a partir do código-fonte
- biblioteca de compatibilidade `android-shmem` modificada
- replicação física por streaming do PostgreSQL entre dispositivos Android ARM64
- clientes PostgreSQL remotos através da rede local
- experimentos de inserção em massa e desempenho com `COPY`

Este repositório documenta não apenas a configuração final, mas também os problemas técnicos encontrados, abordagens que não funcionaram, modificações no código-fonte, testes e decisões que levaram à implementação funcional.

---

## Por que este projeto existe

Executar PostgreSQL em uma distribuição Linux tradicional é relativamente simples.

Executá-lo dentro de um Linux chroot hospedado pelo Android apresenta desafios adicionais.

Embora o Android utilize o kernel Linux, seu userspace e a configuração do kernel podem ser significativamente diferentes de um sistema GNU/Linux convencional.

Um dos principais problemas encontrados durante este experimento foi a compatibilidade com memória compartilhada System V.

Um programa simples de teste inicialmente retornou:

```text
key=74565 size=4096
shmget: Function not implemented
```

O mesmo programa, quando executado com a biblioteca de compatibilidade `android-shmem` modificada através de `LD_PRELOAD`, conseguiu criar, anexar, utilizar, desanexar e remover com sucesso o segmento de memória compartilhada.

Essa camada de compatibilidade tornou-se uma parte importante para conseguir executar o PostgreSQL nos ambientes Android/chroot testados.

---

## Arquitetura atual

```text
                         Rede local
                             |
                +------------+------------+
                |                         |
                v                         v
        Samsung Galaxy A15        Motorola Android One
        Android / Root            Android / Root
        Ubuntu 24.04 chroot       Ubuntu 24.04 chroot
        PostgreSQL 18.6           PostgreSQL 18.6
        ARM64                     ARM64

        PRIMARY                   HOT STANDBY
        192.168.1.50 ---------->  192.168.1.40
                    WAL streaming

        INSERT / UPDATE           SELECT
        SELECT                    Réplica de leitura
```

O Galaxy A15 é atualmente o nó PostgreSQL principal.

O Motorola Android One funciona como réplica física assíncrona por streaming e pode ser utilizado para consultas somente leitura enquanto opera como hot standby.

O objetivo da arquitetura não é deixar o dispositivo principal, que possui maior capacidade, ocioso. Durante a operação normal durante o dia, o A15 pode continuar atendendo consultas de leitura. A réplica Motorola pode fornecer capacidade adicional de leitura quando necessário.

A maior parte das ingestões em massa é esperada em períodos de menor atividade de consultas interativas.

---

## Nó experimental LG K11 Plus

Um terceiro dispositivo Android também foi testado:

```text
LG K11 Plus
Android 7.1.2
Plataforma MediaTek
Android userspace: 32 bits
Kernel reportado: armv7l
Ubuntu 24.04 chroot: armhf
PostgreSQL 18.6: 32 bits
```

O PostgreSQL 18.6 foi compilado e inicializado com sucesso nesse dispositivo após solucionarmos problemas de compatibilidade de memória compartilhada.

O LG K11 Plus atualmente não faz parte da topologia de replicação física. Ele está sendo tratado como um nó experimental de processamento/PostgreSQL enquanto outros dispositivos ARM64 são considerados para o cluster.

---

## Replicação PostgreSQL por streaming

A replicação física por streaming entre o Samsung Galaxy A15 primary e o Motorola Android One standby foi testada com sucesso.

No servidor principal, `pg_stat_replication` informou:

```text
client_addr  = 192.168.1.40
state        = streaming
sync_state   = async
```

Durante a validação, as seguintes posições WAL chegaram ao mesmo LSN:

```text
sent_lsn
write_lsn
flush_lsn
replay_lsn
```

No Motorola standby:

```sql
SELECT pg_is_in_recovery();
```

retornou:

```text
t
```

O `pg_stat_wal_receiver` do standby informou:

```text
status      = streaming
sender_host = 192.168.1.50
sender_port = 5432
```

Uma linha de teste inserida no Galaxy A15 primary foi replicada e posteriormente lida com sucesso no Motorola standby.

Isso confirmou a replicação física por streaming de ponta a ponta entre as duas instalações PostgreSQL hospedadas em dispositivos Android.

---

## O problema da memória compartilhada

O PostgreSQL depende de recursos de memória compartilhada fornecidos pelo sistema operacional.

Dentro do ambiente Android/chroot testado, um teste direto de memória compartilhada System V inicialmente falhou:

```text
shmget: Function not implemented
```

O problema não estava no nível SQL do PostgreSQL. Ele ocorria na camada de compatibilidade com o sistema operacional.

Por isso, o projeto investigou o `android-shmem`, originalmente desenvolvido por pelya:

https://github.com/pelya/android-shmem

A biblioteca fornece implementações de compatibilidade em userspace para funções de memória compartilhada System V utilizando mecanismos disponíveis no ambiente Android/Linux.

---

## Trabalho de compatibilidade com `android-shmem`

O programa de teste utiliza a API tradicional de memória compartilhada System V:

```c
shmget(...)
shmat(...)
shmdt(...)
shmctl(...)
```

Sem a biblioteca de compatibilidade:

```text
shmget: Function not implemented
```

Com a biblioteca modificada carregada:

```bash
LD_PRELOAD=/usr/local/lib/libandroid-shmem.so ./test-shm-key
```

o teste conseguiu prosseguir com sucesso através da alocação e mapeamento da memória compartilhada.

Um exemplo de execução bem-sucedida apresentou:

```text
shmget OK
shmat OK
write/read: android-shmem funcionando
shmdt OK
IPC_RMID OK
```

As modificações específicas deste projeto e os programas de teste reproduzíveis serão mantidos em:

```text
android-shmem/
├── patches/
└── tests/
```

---

## Compatibilidade ARMHF / glibc `shmctl`

Um problema adicional apareceu no ambiente Ubuntu ARMHF/32 bits.

A inspeção do executável de teste mostrou:

```text
shmget@GLIBC_2.4
shmat@GLIBC_2.4
__shmctl64@GLIBC_2.34
shmdt@GLIBC_2.4
```

enquanto a biblioteca de compatibilidade exportava:

```text
shmget
shmat
shmdt
shmctl
```

Essa diferença foi importante porque interceptar somente `shmctl` não significa necessariamente interceptar um binário chamando o símbolo da glibc:

```text
__shmctl64@GLIBC_2.34
```

Foi necessário, portanto, trabalho adicional de compatibilidade nesse ambiente de 32 bits.

Após as alterações, o teste foi concluído com sucesso através das operações:

```text
shmget
shmat
write/read
shmdt
shmctl(IPC_RMID)
```

As modificações exatas no código-fonte serão documentadas separadamente, em vez de ficarem escondidas apenas dentro de uma biblioteca binária pré-compilada.

---

## Inicialização do PostgreSQL

Após o trabalho de compatibilidade de memória compartilhada, o `initdb` do PostgreSQL foi concluído com sucesso dentro do ambiente Ubuntu hospedado pelo Android.

Durante a inicialização, a biblioteca de compatibilidade tratou múltiplas alocações de memória compartilhada.

A inicialização terminou com:

```text
performing post-bootstrap initialization ... ok
syncing data to disk ... ok
```

seguido por:

```text
Success. You can now start the database server using:

    /usr/local/pgsql18/bin/pg_ctl -D /usr/local/pgsql18/data -l logfile start
```

Esse foi um marco importante porque demonstrou que o PostgreSQL conseguiu inicializar um cluster completo de banco de dados no ambiente testado.

---

## Memória compartilhada dinâmica

A configuração PostgreSQL utilizada no ambiente testado inclui:

```conf
dynamic_shared_memory_type = mmap
```

A verificação através do próprio PostgreSQL retornou:

```sql
SHOW dynamic_shared_memory_type;
```

```text
 dynamic_shared_memory_type
----------------------------
 mmap
```

O trabalho realizado com `android-shmem` e a configuração `dynamic_shared_memory_type = mmap` do PostgreSQL tratam mecanismos diferentes de memória compartilhada e não devem ser considerados a mesma configuração.

---

## Compilação do PostgreSQL

A versão do PostgreSQL atualmente testada nos dispositivos Android é:

```text
PostgreSQL 18.6
```

O prefixo de instalação utilizado nos ambientes Android/chroot é:

```text
/usr/local/pgsql18
```

O PostgreSQL foi compilado a partir do código-fonte dentro do Ubuntu 24.04 executado no chroot Android.

Uma das compilações verificadas informou:

```text
PostgreSQL 18.6 on armv7l-unknown-linux-gnueabihf,
compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0,
32-bit
```

As dependências de compilação, opções do `configure`, etapas de compilação e particularidades de cada arquitetura serão documentadas separadamente.

---

## Ubuntu 24.04 Chroot

O Ubuntu 24.04 LTS é utilizado como ambiente userspace GNU/Linux.

O Ubuntu é executado dentro de um chroot hospedado pelo Android e, portanto, utiliza o kernel Linux já em execução no dispositivo Android.

Não se trata de uma máquina virtual.

Conceitualmente:

```text
Smartphone Android
        |
        +-- Kernel Linux
        |
        +-- Android userspace
        |
        +-- Ubuntu 24.04 chroot
                |
                +-- GNU/Linux userspace
                |
                +-- PostgreSQL 18.6
```

Essa distinção é importante.

Um chroot altera a raiz aparente do sistema de arquivos para os processos, mas não fornece um kernel separado. Portanto, os recursos de kernel disponíveis para o PostgreSQL são determinados pelo kernel Android em execução e por sua configuração.

---

## Inicialização do PostgreSQL junto com o chroot

O processo de inicialização do chroot no Android foi modificado para que o PostgreSQL possa ser iniciado automaticamente ao entrar no ambiente Ubuntu.

O projeto utiliza scripts auxiliares dedicados ao PostgreSQL:

```text
/scripts/postgres/start.sh
/scripts/postgres/stop.sh
/scripts/postgres/restart.sh
/scripts/postgres/status.sh
```

Os scripts Android responsáveis pela inicialização e encerramento do chroot também serão documentados.

Durante o encerramento, o PostgreSQL é parado antes que os bind mounts do Ubuntu sejam desmontados. Isso evita desmontar abruptamente o ambiente chroot enquanto o servidor de banco de dados ainda está em execução.

Scripts de exemplo sanitizados serão publicados em:

```text
scripts/android/
scripts/postgres/
```

---

## Acesso pela rede

O PostgreSQL foi acessado com sucesso a partir de outro desktop Ubuntu conectado à mesma rede local.

Durante os testes, o PostgreSQL ficou disponível pela interface de rede e clientes remotos conectaram-se ao servidor hospedado no Android.

O projeto fornecerá exemplos sanitizados de `postgresql.conf` e `pg_hba.conf`, em vez de publicar credenciais reais de produção.

Os endereços de rede apresentados neste repositório são endereços privados RFC1918 de LAN utilizados apenas para descrever a topologia dos testes.

---

## Testes de inserção em massa

A inserção em massa de dados foi testada remotamente a partir de um desktop Ubuntu para o PostgreSQL executado no dispositivo Android.

Um dos testes SQL inseriu:

```sql
INSERT INTO teste_insercao (origem, valor)
SELECT 'desktop_ubuntu', g
FROM generate_series(1, 1000000) AS g;
```

Uma execução medida apresentou:

```text
Registros:       1.000.000
Tempo de execução: 24 segundos
```

Esse resultado representa uma execução experimental específica e não deve ser interpretado como benchmark geral do PostgreSQL ou do Android.

Estado do hardware, armazenamento, condições do Wi-Fi, configuração do PostgreSQL, condições térmicas e outros fatores podem afetar o desempenho.

---

## Testes com `COPY`

A ingestão em massa também foi testada a partir do desktop Ubuntu utilizando `\copy` do PostgreSQL.

Para um milhão de registros gerados:

```bash
awk 'BEGIN {
  for (i=1; i<=1000000; i++)
    print "desktop_ubuntu," i
}' | \
/caminho/para/psql \
  -h IP_DO_SERVIDOR \
  -U postgres \
  -d postgres \
  -c "\copy teste_insercao(origem,valor) FROM STDIN WITH (FORMAT csv)"
```

O resultado foi:

```text
COPY 1000000

real    0m32.513s
user    0m0.702s
sys     0m0.129s
```

Um teste com cinco milhões de registros retornou:

```text
COPY 5000000

real    1m56.230s
user    0m3.520s
sys     0m0.420s
```

Esses são resultados experimentais observados e não constituem comparações controladas de desempenho entre plataformas.

Uma metodologia de benchmark mais rigorosa será adicionada em `benchmarks/`.

---

## Carga de trabalho pretendida

O projeto foi motivado por um cenário real de processamento de dados envolvendo grandes quantidades de registros ingeridos principalmente em lotes.

Após a ingestão, a carga esperada é predominantemente de leitura.

A ideia arquitetural atual é, portanto:

```text
Menor atividade interativa
        |
        +-- ingestão em massa
        +-- manutenção do banco
        +-- replicação

Maior atividade interativa
        |
        +-- primary atende consultas SELECT
        +-- standby permanece disponível para escalar leituras
        +-- consultas adicionais podem ser direcionadas
            às réplicas quando necessário
```

O projeto atualmente não afirma possuir balanceamento automático de consultas PostgreSQL entre os smartphones.

O direcionamento de tráfego de leitura entre primary e standby exige uma camada externa de roteamento/balanceamento ou lógica na aplicação e será investigado separadamente.

---

## O que já foi testado com sucesso

Até o momento, o projeto demonstrou:

- dispositivos Android com root hospedando ambientes Ubuntu 24.04 chroot
- PostgreSQL 18.6 compilado a partir do código-fonte
- PostgreSQL executando em dispositivos Android ARM64
- PostgreSQL executando em ambiente Android ARMHF/32 bits
- compatibilidade de memória compartilhada System V através de `android-shmem` modificado
- execução bem-sucedida do `initdb`
- inicialização e encerramento do servidor PostgreSQL
- conexões PostgreSQL remotas através de Wi-Fi/LAN
- inserções SQL em massa
- ingestão de dados utilizando `COPY`
- replicação física por streaming PostgreSQL entre dois dispositivos Android ARM64
- replicação assíncrona
- operação hot standby
- consultas SELECT realizadas com sucesso no standby Android
- inicialização automática do PostgreSQL como parte da inicialização do chroot
- encerramento controlado do PostgreSQL antes da desmontagem do chroot

---

## Estado experimental

Este é um projeto experimental de pesquisa e engenharia.

Ele não deve ser interpretado atualmente como recomendação para utilizar qualquer smartphone Android como servidor PostgreSQL de produção.

Os resultados podem depender de:

- versão do Android
- configuração do kernel Linux
- arquitetura da CPU
- userspace 32 ou 64 bits
- método utilizado para root
- configuração SELinux
- fabricante do dispositivo
- tecnologia de armazenamento
- memória RAM disponível
- qualidade da rede/Wi-Fi
- limites térmicos
- comportamento da bateria e gerenciamento de energia

Durabilidade em execução prolongada, recuperação de falhas, desgaste do armazenamento, comportamento térmico e alta disponibilidade em nível de produção ainda exigem testes consideravelmente maiores.

---

## Testes planejados

Os próximos experimentos incluem:

- benchmarks de SELECT concorrente
- medição da latência das consultas
- centenas de consultas simultâneas
- comparação da carga de leitura entre primary e standby
- experimentos de roteamento/balanceamento de leitura
- inclusão de outros dispositivos Android ARM64
- medição de utilização da CPU
- medição de utilização da RAM
- medições de I/O do armazenamento
- medições de throughput da rede
- thermal throttling
- consumo de energia
- execução prolongada do PostgreSQL
- recuperação da réplica após interrupção da rede
- recuperação após reinicialização do Android
- atraso da replicação sob carga de escrita
- comportamento enquanto o dispositivo Android está carregando
- outros modelos Android e SoCs

---

## Direção futura: cluster de dispositivos Android

Uma das direções futuras deste projeto é investigar a utilização de múltiplos dispositivos Android físicos trabalhando em conjunto como uma infraestrutura PostgreSQL distribuída de baixo custo.

A arquitetura atual já fornece uma base experimental para essa evolução, com PostgreSQL executado nativamente para a arquitetura ARM dentro do Ubuntu 24.04 em chroot e replicação física por streaming entre dispositivos Android.

O objetivo futuro é expandir os experimentos para uma arquitetura composta por diferentes funções, incluindo:

- um dispositivo Android atuando como servidor PostgreSQL primary;
- um ou mais dispositivos ARM64 atuando como hot standby e servidores de leitura;
- dispositivos adicionais atuando como nós de processamento e ingestão de dados;
- distribuição de consultas de leitura entre primary e réplicas;
- avaliação de diferentes estratégias de roteamento e balanceamento de carga;
- comparação da comunicação entre os dispositivos utilizando Wi-Fi e Ethernet;
- testes de comportamento do conjunto durante falhas ou desconexões temporárias de nós;
- inclusão de novos dispositivos Android para avaliar a expansão horizontal da arquitetura.

A intenção não é afirmar que a configuração atual constitui um cluster PostgreSQL completo ou pronto para produção. O objetivo é investigar experimentalmente até que ponto smartphones Android podem cooperar como nós de uma infraestrutura PostgreSQL, documentando desempenho, limitações, falhas e soluções encontradas em hardware real.

À medida que novos dispositivos e experimentos forem adicionados, os resultados serão documentados neste repositório.

---

## Estrutura do repositório

```text
docs/
├── en/
└── pt-BR/

scripts/
├── android/
└── postgres/

android-shmem/
├── patches/
└── tests/

benchmarks/
├── results/
└── sql/

diagrams/
```

A documentação detalhada será mantida em inglês e português do Brasil.

---

## Projeto upstream

O trabalho relacionado à compatibilidade de memória compartilhada deste projeto é baseado no projeto `android-shmem` de pelya:

https://github.com/pelya/android-shmem

Os direitos autorais e requisitos de licença dos projetos upstream continuam aplicáveis.

As modificações específicas deste projeto serão claramente documentadas e, sempre que possível, distribuídas como patches, em vez de ficarem escondidas dentro de arquivos binários.

Antes da publicação de código-fonte derivado, a licença upstream aplicável será revisada e preservada.

---

## Segurança

Nunca copie senhas reais de banco de dados, credenciais de replicação, chaves privadas, tokens de autenticação ou outros segredos para um repositório público.

As configurações de exemplo deste repositório utilizarão valores fictícios, como:

```text
IP_DO_SERVIDOR
USUARIO_REPLICACAO
SENHA_REPLICACAO
```

Arquivos reais como `postgresql.auto.conf`, `.pgpass`, chaves privadas, tokens e arquivos contendo credenciais não devem ser adicionados ao repositório.

---

## Reprodutibilidade

Um dos principais objetivos deste repositório é permitir a reprodução dos experimentos.

Sempre que possível, a documentação distinguirá claramente:

- comandos realmente executados
- resultados observados
- configurações específicas dos dispositivos
- modificações necessárias para compatibilidade
- conclusões experimentais
- ideias que ainda não foram testadas

Essa distinção é especialmente importante porque kernels e userspaces Android podem variar consideravelmente entre fabricantes e dispositivos.

---

## Contribuições

Este projeto está sendo publicado para que desenvolvedores interessados em PostgreSQL, Android, sistemas ARM, ambientes Linux chroot, compatibilidade de memória compartilhada e computação distribuída possam reproduzir os experimentos em outros hardwares.

Contribuições úteis incluem:

- resultados obtidos em outros dispositivos Android
- relatórios de compatibilidade de kernel e arquitetura
- correções na camada de compatibilidade de memória compartilhada
- resultados de compilação do PostgreSQL
- benchmarks com metodologia documentada
- experimentos de replicação
- melhorias na documentação
- relatórios de erros reproduzíveis

Issues e pull requests serão bem-vindos quando o repositório se tornar público.

---

## Status

**Experimental — funcional e em processo ativo de documentação e testes.**
