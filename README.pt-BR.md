# PostgreSQL 18 em Android com Root e Ubuntu 24.04 Chroot

[English](README.md)

## Visão geral

Este projeto documenta um experimento prático executando PostgreSQL 18.6,
compilado a partir do código-fonte, dentro de um ambiente Ubuntu 24.04 chroot
em dispositivos Android com acesso root.

O projeto começou como uma investigação para verificar se smartphones Android
poderiam ser utilizados como nós reais PostgreSQL para processamento,
armazenamento, replicação e cargas de consulta.

O resultado é um pequeno cluster PostgreSQL funcional utilizando smartphones
Android.

A arquitetura atualmente testada inclui:

- Samsung Galaxy A15 como servidor PostgreSQL principal (primary)
- Motorola Android One (deen) como hot standby/réplica de leitura ARM64
- LG K11 Plus como worker experimental ARMHF/32 bits
- Ubuntu 24.04 executado em ambientes chroot sobre Android
- PostgreSQL 18.6 compilado a partir do código-fonte
- biblioteca de compatibilidade `android-shmem` modificada
- streaming replication PostgreSQL entre dispositivos Android ARM64
- clientes PostgreSQL remotos através da rede local
- experimentos de inserção em massa e desempenho de armazenamento

Este repositório documenta não apenas a configuração final, mas também os
problemas técnicos encontrados, abordagens que não funcionaram, modificações
no código-fonte, testes e decisões que levaram à implementação funcional.

---

## Por que este projeto existe

Executar PostgreSQL em uma distribuição Linux tradicional é relativamente
simples.

Executá-lo dentro de um Linux chroot hospedado pelo Android apresenta
diferenças importantes.

Embora o Android utilize o kernel Linux, seu userspace e a configuração do
kernel podem ser significativamente diferentes de um sistema GNU/Linux
convencional.

Um dos principais problemas encontrados durante este experimento foi o suporte
à memória compartilhada esperado pelo PostgreSQL.

Um teste inicialmente retornou:

```text
shmget: Function not implemented

Para contornar essa limitação, este projeto utiliza e modifica a biblioteca de
compatibilidade android-shmem, originalmente desenvolvida por pelya.

As modificações e os testes utilizados serão documentados detalhadamente neste
repositório.

Arquitetura atual

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

Um terceiro dispositivo testado está sendo utilizado como worker experimental:

LG K11 Plus
MediaTek MT6750
CPU com suporte ARMv8
ambiente Android instalado: 32 bits
kernel reportado: armv7l
Ubuntu 24.04: armhf
PostgreSQL 18.6: 32 bits

O LG não é utilizado atualmente como réplica física do PostgreSQL.

Streaming Replication PostgreSQL

A replicação física por streaming entre o Samsung Galaxy A15 e o Motorola
Android One foi testada com sucesso.

No servidor primary:

client_addr = 192.168.1.40
state       = streaming
sync_state  = async

Durante a validação, as posições WAL chegaram ao mesmo LSN para:

sent_lsn
write_lsn
flush_lsn
replay_lsn

No Motorola standby:

SELECT pg_is_in_recovery();

retornou:

t

O WAL receiver informou:

status      = streaming
sender_host = 192.168.1.50
sender_port = 5432

Uma linha de teste inserida no Galaxy A15 primary foi posteriormente lida com
sucesso no Motorola standby.

Compatibilidade de memória compartilhada

O PostgreSQL espera funcionalidades de memória compartilhada que não estavam
diretamente disponíveis da maneira necessária no ambiente Android/chroot
testado.

O projeto utiliza como base:

https://github.com/pelya/android-shmem

Durante os testes, verificamos que a implementação original rejeitava chaves
de memória compartilhada diferentes de IPC_PRIVATE.

A lógica original relevante era:

if (key != IPC_PRIVATE)
{
    errno = EINVAL;
    return -1;
}

A implementação experimental utilizada neste projeto foi modificada para
permitir as chaves de memória compartilhada necessárias durante a
inicialização do PostgreSQL.

Também foi necessário trabalho adicional de compatibilidade no ambiente
ARMHF/32 bits, onde os binários faziam referência a:

__shmctl64@GLIBC_2.34

enquanto a biblioteca de compatibilidade original exportava:

shmctl

As modificações completas, patches, explicações e testes reproduzíveis serão
incluídos no diretório android-shmem/.

Validação da memória compartilhada

Após as alterações de compatibilidade, o programa de teste apresentou sucesso
nas seguintes operações:

shmget OK
shmat OK
write/read OK
shmdt OK
IPC_RMID OK

Posteriormente, a inicialização do PostgreSQL foi concluída com sucesso dentro
do Ubuntu chroot hospedado pelo Android.

A configuração PostgreSQL utilizada nesse ambiente inclui:

dynamic_shared_memory_type = mmap

Compilação do PostgreSQL

A versão atualmente testada é:

PostgreSQL 18.6

O prefixo de instalação utilizado nos ambientes Android é:

/usr/local/pgsql18

O PostgreSQL é compilado diretamente dentro do Ubuntu 24.04 executado no
chroot.

As dependências, opções de configuração, etapas de compilação e particularidades
de cada arquitetura serão documentadas separadamente.

Ambiente Ubuntu

O ambiente Linux utilizado nos testes é baseado em:

Ubuntu 24.04 LTS

O Ubuntu é executado através de chroot e, portanto, compartilha o kernel Linux
do dispositivo Android.

Não se trata de uma máquina virtual.

Conceitualmente:

Dispositivo Android
        |
        +-- Kernel Linux
               |
               +-- Android userspace
               |
               +-- Ubuntu 24.04 chroot
                       |
                       +-- PostgreSQL 18.6

Essa distinção é importante ao investigar recursos do kernel e o comportamento
da memória compartilhada.

Objetivos do projeto

O projeto investiga se dispositivos Android de baixo custo ou sem utilização
podem participar de cargas PostgreSQL e processamento distribuído.

As áreas investigadas incluem:

PostgreSQL em Android com root
nós PostgreSQL ARM64
experimentos PostgreSQL ARMHF
compatibilidade de memória compartilhada
ingestão de grandes volumes de dados
desempenho de leitura
streaming replication PostgreSQL
consultas em hot standby
workers para processamento distribuído
cargas de SELECT concorrentes
desempenho de armazenamento
desempenho de rede
comportamento térmico
estabilidade em execução prolongada
O que já foi testado com sucesso

Até o momento, o projeto demonstrou com sucesso:

Ubuntu 24.04 chroot em Android com root
PostgreSQL 18.6 compilado a partir do código-fonte
PostgreSQL executando em Android ARM64
PostgreSQL executando em ambiente Android ARMHF/32 bits
compatibilidade de memória compartilhada usando android-shmem modificado
inicialização do PostgreSQL dentro do chroot
acesso ao PostgreSQL pela rede a partir de outros computadores
inserções em massa
ingestão de dados utilizando COPY
streaming replication físico entre dois dispositivos Android ARM64
operação hot standby
consultas SELECT na réplica Android
Estado experimental

Este é um projeto experimental de pesquisa.

Ele não deve ser interpretado atualmente como recomendação para utilizar
qualquer smartphone Android como servidor PostgreSQL de produção.

Os resultados podem depender de:

versão do Android
configuração do kernel Linux
arquitetura da CPU
userspace 32 ou 64 bits
método utilizado para root
configuração SELinux
fabricante do dispositivo
tecnologia de armazenamento
limites térmicos
quantidade de memória RAM disponível

O repositório procura distinguir resultados experimentalmente comprovados de
trabalhos futuros.

Testes planejados

Os próximos experimentos incluem:

benchmarks de SELECT concorrente
medição de latência das consultas
centenas de consultas simultâneas
overflow de leitura do primary para a réplica
inclusão de outros dispositivos Android ARM64
medição de utilização de CPU
utilização de RAM
medições de I/O do armazenamento
thermal throttling
consumo de energia
execução prolongada do PostgreSQL
recuperação da réplica após interrupção da rede
recuperação após reinicialização do Android

Estrutura do repositório

docs/
    en/
    pt-BR/

scripts/
    android/
    postgres/

android-shmem/
    patches/
    tests/

benchmarks/
    results/
    sql/

diagrams/

A documentação detalhada será mantida em inglês e português do Brasil.

Projeto upstream

O trabalho relacionado à compatibilidade de memória compartilhada deste
projeto é baseado no projeto android-shmem de pelya:

https://github.com/pelya/android-shmem

Os direitos autorais e requisitos de licença dos projetos upstream continuam
aplicáveis.

Sempre que possível, as modificações específicas deste projeto serão mantidas
separadamente e documentadas como patches.

Segurança

Nunca copie senhas reais de banco de dados, credenciais de replicação, chaves
privadas, identificadores dos dispositivos ou arquivos de configuração de
produção diretamente para um repositório público.

As configurações de exemplo deste projeto utilizarão credenciais fictícias.

Contribuições

Este projeto está sendo publicado para que outros desenvolvedores interessados
em PostgreSQL, Android, sistemas ARM, ambientes chroot e computação distribuída
possam reproduzir os experimentos, informar resultados em outros dispositivos
e contribuir com melhorias.

Issues, correções técnicas, resultados reproduzíveis e contribuições são
bem-vindos.

Status

Experimental, funcional e em processo ativo de documentação e testes.

```text
