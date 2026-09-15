# Scripts de controle do Android Chroot e PostgreSQL

[English](README.md)

## Visão geral

Este diretório contém os scripts shell utilizados para controlar o ambiente Ubuntu 24.04 chroot e o PostgreSQL 18.6 nos dispositivos Android testados por este projeto.

A mesma estrutura de diretórios e os mesmos nomes de scripts são utilizados em todos os dispositivos atualmente testados:

- Samsung Galaxy A15 — ARM64
- Motorola Android One (deen) — ARM64
- LG K11 Plus — ARMHF/32 bits

Os scripts preservados neste repositório foram extraídos diretamente do ambiente funcional do Samsung Galaxy A15 e verificados antes da publicação.

A estrutura operacional é:

```text
Android
/data/local/
├── start-ubuntu.sh
├── stop-ubuntu.sh
└── ubuntu24/
    └── scripts/
        └── postgres/
            ├── start.sh
            ├── stop.sh
            ├── restart.sh
            └── status.sh
```

Dentro do Ubuntu chroot, os scripts PostgreSQL aparecem como:

```text
/scripts/postgres/
├── start.sh
├── stop.sh
├── restart.sh
└── status.sh
```

---

## Por que utilizamos scripts em vez de systemd

O Ubuntu 24.04 deste projeto é executado como um chroot hospedado pelo Android.

Não se trata de uma máquina virtual e o Ubuntu não inicializa seu próprio kernel Linux nem um sistema init convencional independente.

Por esse motivo, o ciclo de vida do PostgreSQL é controlado explicitamente por scripts, em vez de depender de uma sequência normal de inicialização via `systemd` dentro do chroot.

O fluxo básico de inicialização é:

```text
Android
   |
   v
start-ubuntu.sh
   |
   +--> monta /dev
   +--> monta /dev/pts
   +--> monta /proc
   +--> monta /sys
   |
   v
Ubuntu 24.04 chroot
   |
   v
/scripts/postgres/status.sh
   |
   +--> PostgreSQL já está rodando -> continua
   |
   +--> PostgreSQL parado
             |
             v
       /scripts/postgres/start.sh
             |
             v
          setpriv
             |
             v
       usuário postgres
             |
             v
         LD_PRELOAD
             |
             v
    libandroid-shmem.so
             |
             v
           pg_ctl
```

---

## Scripts do Android

Os scripts presentes em:

```text
scripts/android/
```

são executados no lado Android do ambiente.

Eles utilizam:

```text
#!/system/bin/sh
```

e necessitam de privilégios suficientes para realizar mounts e entrar no chroot.

Nos dispositivos rooteados testados, eles são executados com privilégios de root.

### `start-ubuntu.sh`

O script de inicialização define a raiz do Ubuntu como:

```text
/data/local/ubuntu24
```

Ele prepara os seguintes mounts:

```text
/dev
/dev/pts
/proc
/sys
```

Antes de montar cada um deles, o script verifica se o mount já existe, evitando mounts duplicados desnecessários.

Também são preparadas variáveis de ambiente como:

```text
TMPDIR=/tmp
TMP=/tmp
TEMP=/tmp
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LANG=en_US.UTF-8
```

Antes de abrir o shell interativo do Ubuntu, o PostgreSQL é verificado através de:

```text
/scripts/postgres/status.sh
```

Se o PostgreSQL já estiver em execução, ele não é reiniciado.

Caso contrário:

```text
/scripts/postgres/start.sh
```

é executado automaticamente.

Finalmente, o ambiente Ubuntu é aberto com:

```bash
exec chroot "$ROOT" /bin/bash
```

Assim, entrar no Ubuntu também garante que o PostgreSQL esteja disponível.

---

## Encerramento seguro

O `stop-ubuntu.sh` realiza o processo inverso.

O PostgreSQL é encerrado **antes** da desmontagem dos recursos associados ao chroot.

O fluxo é:

```text
stop-ubuntu.sh
       |
       v
/scripts/postgres/stop.sh
       |
       v
aguarda PostgreSQL
       |
       +--> falha
       |      |
       |      +--> cancela desmontagem
       |
       +--> encerrado
              |
              v
         pequena espera
              |
              v
        desmonta /dev/pts
        desmonta /dev
        desmonta /proc
        desmonta /sys
```

Essa ordem é intencional.

Se `stop.sh` retornar erro, `stop-ubuntu.sh` informa:

```text
ERRO: PostgreSQL nao foi parado.
Ubuntu NAO sera desmontado.
```

e termina sem desmontar o ambiente Ubuntu.

Isso evita que o ambiente do chroot seja desmontado enquanto o processo PostgreSQL ainda possa estar em execução.

O script também verifica o status do PostgreSQL durante aproximadamente dez segundos e realiza uma pequena espera adicional antes da desmontagem.

---

## Scripts PostgreSQL

Os scripts presentes em:

```text
scripts/postgres/
```

são executados dentro do Ubuntu 24.04 chroot.

Todos os scripts atualmente preservados utilizam:

```text
PGHOME=/usr/local/pgsql18
PGDATA=$PGHOME/data
SHMEM=/usr/local/lib/libandroid-shmem.so
```

Portanto, a estrutura esperada é:

```text
/usr/local/pgsql18/
├── bin/
├── data/
└── logfile

/usr/local/lib/
└── libandroid-shmem.so
```

---

## Execução como usuário `postgres`

O ambiente Android/chroot exige alguns cuidados diferentes de um servidor Ubuntu convencional.

Os scripts PostgreSQL utilizam:

```bash
setpriv \
  --reuid=postgres \
  --regid=postgres \
  --groups=1000,3003
```

Isso altera a execução do usuário root do chroot para a conta não privilegiada `postgres`, mantendo os grupos suplementares necessários no ambiente Android testado.

Os números dos grupos são específicos do ambiente e não devem ser copiados cegamente para dispositivos diferentes.

Quem reproduzir o projeto deve verificar quais grupos são necessários em seu próprio ambiente Android/chroot.

---

## `LD_PRELOAD`

O PostgreSQL é iniciado com:

```bash
env LD_PRELOAD=/usr/local/lib/libandroid-shmem.so
```

Isso faz com que a biblioteca modificada de compatibilidade `android-shmem`, documentada em outra parte deste repositório, seja carregada no processo PostgreSQL.

A execução finalmente chama:

```text
/usr/local/pgsql18/bin/pg_ctl
```

utilizando o diretório de dados:

```text
/usr/local/pgsql18/data
```

A biblioteca de compatibilidade e seu patch estão documentados em:

```text
android-shmem/
```

---

## Iniciando o PostgreSQL

O `start.sh` executa:

```text
pg_ctl -D $PGDATA -l $PGHOME/logfile start
```

através de `setpriv` e com a biblioteca de compatibilidade carregada por `LD_PRELOAD`.

O log do servidor é gravado em:

```text
/usr/local/pgsql18/logfile
```

---

## Parando o PostgreSQL

O `stop.sh` executa:

```text
pg_ctl -D $PGDATA stop
```

utilizando o mesmo ambiente de usuário e compatibilidade.

O `stop-ubuntu.sh` do Android depende do código de saída desse script.

Se o PostgreSQL não puder ser encerrado corretamente, os mounts do Ubuntu são intencionalmente mantidos.

---

## Reiniciando o PostgreSQL

O `restart.sh` executa:

```text
pg_ctl -D $PGDATA -l $PGHOME/logfile restart
```

utilizando a mesma configuração de `setpriv` e `LD_PRELOAD`.

Esse script é útil após alterações de configuração do PostgreSQL.

---

## Verificando o status

O `status.sh` executa:

```text
pg_ctl -D $PGDATA status
```

no mesmo ambiente de execução.

Ele também é utilizado automaticamente pelos scripts Android de inicialização e encerramento.

---

## Uso manual

A partir de um shell Android com root:

```bash
su
cd /data/local
./start-ubuntu.sh
```

O script monta os pseudo-filesystems necessários, inicia o PostgreSQL se necessário e entra no Ubuntu chroot.

Dentro do Ubuntu:

```bash
/scripts/postgres/status.sh
```

verifica o PostgreSQL.

Para reiniciá-lo:

```bash
/scripts/postgres/restart.sh
```

Para sair do shell Ubuntu:

```bash
exit
```

Depois, o ambiente Ubuntu pode ser encerrado com segurança no Android:

```bash
cd /data/local
./stop-ubuntu.sh
```

---

## Permissões dos arquivos

Os scripts de controle do Android precisam ser executáveis:

```bash
chmod 755 /data/local/start-ubuntu.sh
chmod 755 /data/local/stop-ubuntu.sh
```

Os scripts PostgreSQL também precisam de permissão de execução:

```bash
chmod 755 /data/local/ubuntu24/scripts/postgres/*.sh
```

Dentro do chroot eles aparecem como:

```text
/scripts/postgres/*.sh
```

---

## Padronização entre dispositivos

Os mesmos nomes de scripts e a mesma estrutura de diretórios são utilizados atualmente nos dispositivos Android testados.

Essa padronização facilita a administração porque os comandos operacionais permanecem iguais mesmo quando a arquitetura da CPU ou o hardware do aparelho são diferentes.

Sempre que possível, diferenças específicas de cada dispositivo devem permanecer fora desses scripts.

Exemplos de características dependentes do aparelho:

- arquitetura da CPU
- userspace de 32 ou 64 bits
- kernel Android
- grupos suplementares necessários
- arquitetura da compilação PostgreSQL
- requisitos de compatibilidade de memória compartilhada

---

## Integridade dos scripts extraídos

Os scripts preservados atualmente neste repositório foram extraídos do ambiente funcional do Samsung Galaxy A15.

Valores SHA-256 no momento da extração:

```text
07307437f40902c2f7e91b7f129f4b3bd790a0772ba381ce1cbc2ca6e89ba363  android/start-ubuntu.sh
1f16294c73eb4a73a8ee91df8b59abbb5c45424e05b32b2562163e5214c5ae05  android/stop-ubuntu.sh
634aaed3ebbb14fffc427386e6be3b6e9c6a47bae0eb0398f6640deb27979dba  postgres/restart.sh
ac09d0d0bf68fe1aace71a2cb47de83e73d7be5a0207f51508dd74dab09c9b38  postgres/start.sh
45c344e8aa3aa488b37fc289d141e00064811d8637c4e7b5bca963b90d3d8cc7  postgres/status.sh
508dedce15bf5642a8ccec494b45615271f513fd305d08c6e9e7354117b985ef  postgres/stop.sh
```

Os hashes permaneceram idênticos após a transferência para o desktop de desenvolvimento.

A alteração apenas das permissões de execução não modifica esses SHA-256, pois o hash representa o conteúdo do arquivo e não os metadados de permissão do filesystem.

---

## Segurança

Esses scripts intencionalmente não contêm senhas PostgreSQL, credenciais de replicação, chaves privadas, tokens ou strings de conexão de produção.

Não adicione credenciais reais diretamente nesses arquivos ao adaptá-los.

Configurações contendo informações de autenticação devem ser tratadas separadamente e excluídas de repositórios públicos.

---

## Estado experimental

Esses scripts representam a configuração utilizada por este projeto experimental.

Eles devem ser revisados e adaptados antes de serem utilizados em outro dispositivo.

Em especial, não assuma que:

```text
--groups=1000,3003
```

seja apropriado para outro Android.

Verifique ownership, IDs de grupos, comportamento dos mounts, implementação de root, SELinux, versão do Android e localização do chroot antes da utilização.
