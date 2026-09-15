# Ubuntu 24.04 Chroot em Android com Root

[English](README.md)

## Visão geral

Este documento descreve o procedimento utilizado neste projeto para instalar o Ubuntu 24.04 como ambiente chroot em dispositivos Android com acesso root.

O procedimento ARM64 foi testado em:

- Samsung Galaxy A15
- Motorola One (`deen`)

Os dois dispositivos utilizam a mesma estrutura de diretórios e as mesmas convenções de inicialização:

```text
/data/local/ubuntu24
```

O Ubuntu é executado como **chroot**, e não como máquina virtual.

Portanto, o Ubuntu utiliza o kernel Linux do próprio dispositivo Android e pode acessar recursos do kernel expostos ao chroot, incluindo as interfaces de rede do aparelho.

O LG K11 Plus utilizado neste projeto é diferente porque o ambiente Android instalado nele é ARM de 32 bits. Sua configuração ARMHF é documentada separadamente nos pontos em que existem diferenças específicas de arquitetura.

---

## Ambiente utilizado neste projeto

As instalações ARM64 documentadas aqui utilizam:

```text
Ubuntu Base:   24.04.4 LTS
Arquitetura:   ARM64 / aarch64
Arquivo rootfs: ubuntu-base-24.04.4-base-arm64.tar.gz
Diretório:     /data/local/ubuntu24
```

O SHA-256 do rootfs verificado durante as instalações foi:

```text
04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2
```

Sempre confira o checksum da imagem efetivamente baixada com o checksum publicado pelo Ubuntu para aquela versão.

---

## Arquitetura

O ambiente pode ser representado assim:

```text
Dispositivo Android
        |
        +-- Kernel Linux
               |
               +-- Android userspace
               |
               +-- Ubuntu 24.04 chroot
                       |
                       +-- GNU/Linux userspace
                       |
                       +-- PostgreSQL
```

O Ubuntu chroot não inicializa outro kernel Linux.

Essa diferença é especialmente importante ao lidar com memória compartilhada, rede, permissões de processos e outras funcionalidades dependentes do kernel.

---

## Requisitos

Antes de começar, o dispositivo Android precisa possuir acesso root.

O procedimento também pressupõe:

- acesso ADB a partir de um computador Linux
- espaço livre suficiente em `/data`
- arquitetura compatível com o rootfs Ubuntu escolhido
- conexão de rede funcional no Android
- shell com privilégios root no Android

Confirme que o dispositivo aparece:

```bash
adb devices -l
```

Não publique números seriais reais dos aparelhos sem necessidade.

Nesta documentação:

```text
<DEVICE_SERIAL>
```

representa o serial apresentado por `adb devices`.

---

## 1. Verificar a arquitetura do Android

Antes de baixar o rootfs, verifique a arquitetura do dispositivo.

No computador:

```bash
adb -s <DEVICE_SERIAL> shell
```

Depois:

```bash
uname -m
getprop ro.product.cpu.abi
getprop ro.product.cpu.abilist
```

Nos dispositivos ARM64 utilizados neste projeto, o ambiente é compatível com o Ubuntu Base ARM64.

Não presuma que uma CPU capaz de executar ARMv8 significa necessariamente que o Android instalado seja de 64 bits.

O LG K11 Plus utilizado neste projeto é um exemplo de aparelho com processador capaz de ARMv8, mas com ambiente Android de 32 bits.

---

## 2. Baixar o Ubuntu Base

O rootfs ARM64 utilizado durante estes experimentos foi:

```text
ubuntu-base-24.04.4-base-arm64.tar.gz
```

Ele foi obtido nos releases oficiais do Ubuntu Base.

No computador Linux, para reproduzir exatamente a versão utilizada nos experimentos:

```bash
cd ~/Downloads

wget https://cdimage.ubuntu.com/ubuntu-base/releases/24.04.4/release/ubuntu-base-24.04.4-base-arm64.tar.gz
```

Confira o arquivo:

```bash
ls -lh ubuntu-base-24.04.4-base-arm64.tar.gz

sha256sum ubuntu-base-24.04.4-base-arm64.tar.gz
```

Para o rootfs utilizado neste projeto, o resultado foi:

```text
04207713ece899c3740823d33690441ad3a7f0ded1101aca744e2b0f37ac7ff2
```

---

## 3. Transferir o rootfs por ADB

Envie o arquivo para um diretório temporário do Android:

```bash
adb -s <DEVICE_SERIAL> push \
  ~/Downloads/ubuntu-base-24.04.4-base-arm64.tar.gz \
  /data/local/tmp/
```

Entre no shell:

```bash
adb -s <DEVICE_SERIAL> shell
```

Obtenha root:

```bash
su
```

Verifique novamente o arquivo transferido:

```bash
ls -lh /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz

sha256sum /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz
```

A segunda verificação do SHA-256 é proposital.

Ela confirma que o arquivo presente no Android é idêntico ao arquivo que foi verificado no computador.

---

## 4. Verificar o espaço disponível

Antes de extrair:

```bash
df -h /data
```

Confira também a estrutura existente:

```bash
ls -lah /data/local
```

Isso é especialmente importante quando já existe outro Linux chroot no dispositivo.

Durante a migração do Galaxy A15 utilizada neste projeto, existiram temporariamente:

```text
/data/local/ubuntu    ambiente Ubuntu 22.04 antigo
/data/local/ubuntu24  ambiente Ubuntu 24.04 novo
```

O novo ambiente foi instalado separadamente justamente para não sobrescrever o antigo.

---

## 5. Criar o diretório do Ubuntu 24.04

Como root do Android:

```bash
mkdir -p /data/local/ubuntu24
```

Depois:

```bash
cd /data/local/ubuntu24
```

---

## 6. Extrair o Ubuntu Base

Extraia o rootfs:

```bash
tar -xzf /data/local/tmp/ubuntu-base-24.04.4-base-arm64.tar.gz
```

Confira o resultado:

```bash
ls -la /data/local/ubuntu24 | head -30
```

A instalação utilizada neste projeto apresentou a estrutura padrão com `/usr` unificado:

```text
bin  -> usr/bin
lib  -> usr/lib
sbin -> usr/sbin
```

Confira:

```bash
ls -l /data/local/ubuntu24/bin
ls -l /data/local/ubuntu24/lib
ls -l /data/local/ubuntu24/sbin
```

---

## 7. Montar os sistemas necessários

Antes de entrar no chroot:

```bash
mount --bind /dev /data/local/ubuntu24/dev
mount --bind /dev/pts /data/local/ubuntu24/dev/pts
mount -t proc proc /data/local/ubuntu24/proc
mount -t sysfs sysfs /data/local/ubuntu24/sys
```

O ambiente testado não precisou de uma montagem separada para `/run`.

Essas montagens são importantes porque o chroot compartilha o kernel Linux do Android.

---

## 8. Configurar o DNS

No ambiente testado utilizamos:

```bash
rm -f /data/local/ubuntu24/etc/resolv.conf
```

Depois:

```bash
echo 'nameserver 1.1.1.1' > /data/local/ubuntu24/etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /data/local/ubuntu24/etc/resolv.conf
```

Confira:

```bash
cat /data/local/ubuntu24/etc/resolv.conf
```

Configuração esperada:

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
```

---

## 9. Configurar `/etc/hosts`

Crie:

```bash
cat > /data/local/ubuntu24/etc/hosts <<'EOF'
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
EOF
```

Isso evita problemas de resolução de `localhost` dentro do chroot.

---

## 10. Entrar no Ubuntu

Execute:

```bash
chroot /data/local/ubuntu24 /bin/bash
```

Na instalação mínima do Ubuntu Base pode inicialmente aparecer:

```text
bash: groups: command not found
```

Essa mensagem apareceu durante a instalação testada e não impediu o funcionamento do chroot.

---

## 11. Preparar o ambiente do shell

Dentro do Ubuntu:

```bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

export TMPDIR=/tmp
export TMP=/tmp
export TEMP=/tmp
```

As variáveis relacionadas ao diretório temporário são particularmente úteis nesse ambiente Android/chroot, pois determinadas instalações e compilações podem tentar utilizar locais temporários inadequados herdados do Android.

---

## 12. Verificar o Ubuntu

Confira a distribuição:

```bash
cat /etc/os-release
```

Confira a arquitetura:

```bash
uname -m
```

Nas instalações ARM64:

```text
aarch64
```

Confira também:

```bash
echo "$PATH"
echo "$TMPDIR"
```

---

## 13. Testar o DNS

Por exemplo:

```bash
getent hosts ports.ubuntu.com
```

Uma resolução bem-sucedida confirma que o DNS está funcionando dentro do chroot.

---

## 14. Configurar o APT para o chroot Android

Uma configuração especial do APT foi utilizada com sucesso nos ambientes Android/chroot testados:

```bash
cat > /etc/apt/apt.conf.d/99android-chroot <<'EOF'
APT::Sandbox::User "root";
Acquire::ForceIPv4 "true";
EOF
```

Confira:

```bash
cat /etc/apt/apt.conf.d/99android-chroot
```

Depois:

```bash
apt update
```

Durante uma das instalações documentadas no Galaxy A15, o `apt update` foi concluído normalmente e baixou aproximadamente 35,8 MB de metadados.

O resultado importante é que o acesso aos repositórios funcionou corretamente dentro do chroot.

---

## 15. Atualizar o ambiente base

Depois de um `apt update` bem-sucedido:

```bash
DEBIAN_FRONTEND=noninteractive apt upgrade -y
```

Depois:

```bash
dpkg --configure -a
```

O frontend não interativo é útil nesse ambiente chroot mínimo.

---

## 16. Instalar ferramentas de rede

O Ubuntu Base é propositalmente mínimo.

Por exemplo, inicialmente o comando `ip` não estava disponível.

Instale:

```bash
apt install -y iproute2
```

Depois o próprio chroot consegue visualizar as interfaces de rede do Android:

```bash
ip link show wlan0
ip -4 addr show wlan0
ip route
```

Isso demonstra uma característica importante da arquitetura: o Ubuntu chroot utiliza a rede fornecida pelo dispositivo Android, em vez de uma interface de rede virtual pertencente a uma VM.

---

## 17. Ferramentas de compilação

Antes das etapas posteriores do projeto, confira:

```bash
which gcc
which make
which wget
which curl
which git
```

No ambiente preparado, os caminhos esperados são semelhantes a:

```text
/usr/bin/gcc
/usr/bin/make
/usr/bin/wget
/usr/bin/curl
/usr/bin/git
```

Instale as ferramentas de desenvolvimento que estiverem faltando antes de prosseguir para `android-shmem` e PostgreSQL.

---

## 18. Scripts de inicialização e encerramento

Este repositório contém os scripts realmente utilizados nos aparelhos testados:

```text
scripts/android/start-ubuntu.sh
scripts/android/stop-ubuntu.sh
```

O script de inicialização monta os sistemas necessários e entra no chroot.

A versão atual do projeto também integra a inicialização do PostgreSQL.

O script de encerramento para o PostgreSQL antes de desmontar o ambiente Ubuntu.

Isso é importante: não desmonte os sistemas do chroot enquanto o PostgreSQL ainda estiver em execução.

Consulte:

```text
../scripts/README.pt-BR.md
```

para a documentação específica dos scripts.

---

## 19. Rede compartilhada

Como estamos utilizando chroot e não uma VM, podemos representar a rede assim:

```text
                     Dispositivo Android
                              |
                           wlan0
                              |
                         Kernel Linux
                         /          \
                        /            \
              Android userspace   Ubuntu chroot
                                      |
                                  PostgreSQL
```

Se o Android possuir, por exemplo:

```text
192.168.1.50
```

o PostgreSQL executado dentro do Ubuntu chroot pode atender através da interface de rede do aparelho quando o PostgreSQL e o ambiente Android estiverem configurados adequadamente.

Não existe um segundo endereço IP apenas porque o Ubuntu está sendo executado em chroot.

---

## 20. Reinicialização do Android

As montagens utilizadas pelo chroot não são permanentes.

Depois de reinicializar o dispositivo, elas precisam ser realizadas novamente antes de utilizar o Ubuntu.

Essa é uma das razões pelas quais o projeto utiliza:

```text
/data/local/start-ubuntu.sh
```

para preparar o ambiente de maneira consistente.

---

## 21. ARM64 versus ARMHF

Não escolha o rootfs Ubuntu apenas pelas especificações comerciais da CPU.

Verifique o ambiente efetivamente executado pelo aparelho.

As instalações do Galaxy A15 e Motorola One documentadas aqui utilizam ARM64/aarch64.

O experimento com o LG K11 Plus utiliza um ambiente ARM de 32 bits e, portanto, exigiu Ubuntu ARMHF e trabalho adicional de compatibilidade nas etapas posteriores.

Essa diferença é especialmente importante durante a compilação do PostgreSQL e do `android-shmem`.

---

## 22. Próximas etapas

Depois que o Ubuntu estiver funcionando corretamente, o projeto segue para:

```text
Ubuntu 24.04 chroot
        |
        v
ferramentas de desenvolvimento
        |
        v
android-shmem
        |
        v
patch de compatibilidade PostgreSQL
        |
        v
validação da memória compartilhada
        |
        v
compilação do PostgreSQL 18.6
        |
        v
initdb
        |
        v
scripts do PostgreSQL
        |
        v
acesso pela rede e replicação
```

A compatibilidade de memória compartilhada está documentada em:

```text
../android-shmem/
```

Os scripts operacionais estão documentados em:

```text
../scripts/
```

---

## Segurança

Acesso root concede ao chroot acesso significativo ao dispositivo Android.

Portanto, compreenda os comandos antes de executá-los.

Principalmente:

- confira os caminhos antes de utilizar `rm`
- confira os pontos de montagem antes de montar ou desmontar
- não sobrescreva outro chroot acidentalmente
- não publique números seriais reais dos dispositivos
- não publique credenciais
- não publique chaves privadas
- não publique configurações PostgreSQL de produção contendo senhas

---

## Estado experimental

Este projeto documenta um ambiente experimental.

O procedimento funcionou nos dispositivos testados pelo projeto, mas kernels Android, SELinux, métodos de root, layouts de armazenamento e modificações dos fabricantes podem variar significativamente.

Um chroot funcional não garante sozinho que o PostgreSQL funcionará.

O trabalho de compatibilidade de memória compartilhada documentado em outra parte deste repositório foi necessário para os ambientes PostgreSQL testados neste projeto.

---

## Estrutura padronizada utilizada

A estrutura utilizada nos dispositivos ARM64 é:

```text
/data/local/ubuntu24
/usr/local/pgsql18
/usr/local/lib/libandroid-shmem.so
/scripts/postgres
```

Manter os mesmos caminhos entre os dispositivos simplificou os testes, a configuração da replicação e a manutenção.

---

## Status do projeto

Instalação do Ubuntu 24.04 chroot: **testada e funcional**

Dispositivos ARM64 testados:

```text
Samsung Galaxy A15
Motorola One (deen)
```

Experimento adicional ARMHF/32 bits:

```text
LG K11 Plus
```
