# VM do formador no Proxmox — ambiente comum

O script cria uma VM **Ubuntu 26.04 LTS** com a mesma preparação dos formandos. CP4 usa `~/cp4/compose.yaml`, projeto `cp4`, serviço `app`, volume `cp4_dados`, destino `/dados` e porta 8000. Nginx, Restic, Agent 2 e os modelos systemd ficam no Ubuntu, nos mesmos caminhos do [ambiente comum](../../AMBIENTE_COMUM.md).

O servidor Zabbix e a CA são os da sala. A preparação instala apenas o certificado **público** da CA na VM. Não copia a chave privada.

## 1. Criar ou adaptar

No terminal do **Proxmox, como root**:

```bash
cd /root
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/Skullclamp/adm-srv/main/formador/proxmox/criar-vm-formador.sh \
  -o criar-vm-formador.sh
```

Para uma VM nova:

```bash
bash criar-vm-formador.sh criar
```

Para a VM criada pela versão anterior, conservando o VMID e os dados:

```bash
bash criar-vm-formador.sh alinhar
```

O script lê o IP do Zabbix do ficheiro privado `/root/laboratorio/lab.conf` e usa `/root/laboratorio/segredos/ca-lab.crt`. Se a tua preparação estiver noutro local, indica os valores:

```bash
bash criar-vm-formador.sh alinhar \
  --ip-zabbix IP_DO_SERVIDOR_ZABBIX \
  --ca-cert CAMINHO_DO_CERTIFICADO_PUBLICO
```

## 2. Recursos e parâmetros

| Parâmetro | Valor inicial |
|---|---|
| Sistema / conta | Ubuntu 26.04 LTS; ubuntu / ubuntu |
| Nome da VM / posto | formador-docker / formador |
| VMID | ID livre consultado no cluster |
| CPU / RAM | 4 vCPU tipo host; 8192 MB fixos |
| Disco do sistema | 64 GB |
| Disco de backup | 10 GB, scsi1, serial lab-backup-VMID |
| Storage de discos / snippets | local-lvm / local |
| Bridge / rede | vmbr0 / DHCP |
| Arranque da VM | Automático com o anfitrião |

O identificador `formador` ocupa o lugar de `p1`, `p2` ou `p3` nos parâmetros. Por exemplo, `/var/www/$POSTO` segue a mesma regra em todos os postos. IP, nome do site, hostname Zabbix e PSK são próprios de cada posto para evitar colisões; os comandos e a estrutura das pastas são comuns.

As opções `--vmid`, `--nome`, `--storage`, `--snippets-storage`, `--bridge`, `--vlan`, `--ip`, `--gateway`, `--dns`, `--cores`, `--ram`, `--disco` e `--posto` permitem escolher a primeira configuração. Consulta:

```bash
bash criar-vm-formador.sh ajuda
```

Exemplo com 4096 MB:

```bash
bash criar-vm-formador.sh criar --ram 4096
```

Depois da criação, os valores ficam registados em `/root/adm-srv-formador-vm/parametros.sh`. Atribuições diferentes das registadas são recusadas. `--espera SEGUNDOS` pode ser ajustado quando repetes um comando.

O script verifica o SHA256 da imagem cloud oficial e a disponibilidade do VMID. A identidade da VM é comparada pelo marcador privado na API JSON, incluindo a recusa de templates. No storage de snippets, acrescenta apenas o tipo `snippets` quando estiver em falta e conserva os tipos existentes.

## 3. Adaptação da VM antiga

`alinhar` usa o marcador e VMID já guardados. Acrescenta o disco de backup se scsi1 estiver livre; pode reiniciar a VM para o reconhecer, terminando uma sessão SSH aberta. Se existir outro disco em scsi1, interrompe para revisão, sem o substituir.

A preparação comum guarda a configuração privada antiga em `/var/lib/adm-srv-posto/migracao-*`, para apenas os contentores do projeto antigo e conserva todos os volumes. Copia os dados do volume antigo para `cp4_dados`, verificando hashes. Se o destino já contiver dados diferentes, interrompe sem os sobrepor. Os backups cifrados antigos ficam no respetivo volume, com o segredo conservado na cópia de configuração.

Quando a cópia inicial termina, um marcador associa a migração à identidade do volume de destino. Repetições conservam os dados atuais e os trabalhos da aula. O registo de conclusão da primeira versão comum também permite reconhecer a migração já efetuada. Um volume substituído exige revisão antes de continuar.

O instalador escreve em `~/cp4` e gera `~/parametros-posto.sh`. Os ficheiros de dados existentes são conservados. Uma ficha anterior é guardada antes de gerar a ficha atual. Um Compose existente incompatível é conservado e exige revisão.

O repositório da VM passa para a versão comum indicada no script; alterações locais ao código impedem essa atualização automática. Os dados privados da stack antiga ficam fora da alteração dos ficheiros Git.

## 4. Continuar a aula

Quando a preparação terminar, entra na VM Ubuntu:

```bash
source "$HOME/parametros-posto.sh"
validar_parametros
cd "$HOME/cp4"
sudo docker compose ps
```

Segue o [guia de resolução T0–T17](../GUIA_RESOLUCAO.md). A preparação não resolve antecipadamente a publicação do site, a emissão TLS, os backups de treino, o timer ou o registo do host no Zabbix. Assim, formador e formandos executam os mesmos passos.

No Proxmox, podes consultar:

```bash
bash criar-vm-formador.sh estado
bash criar-vm-formador.sh acessos
bash criar-vm-formador.sh verificar
```

`verificar` confirma os pré-requisitos, CP4, amostra T1, CA pública, Agent 2 e disco de backup. O estado `pronto` indica que essa preparação terminou. HTTPS e monitorização central são verificados nas tarefas respetivas.

## 5. Windows

No PowerShell, usa o IP apresentado para abrir SSH:

```powershell
ssh ubuntu@IP_DA_VM
```

Para encaminhar as portas comuns para o browser do Windows:

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 8000:127.0.0.1:8000 -L 8080:127.0.0.1:80 -L 8443:127.0.0.1:443 ubuntu@IP_DA_VM
```

CP4 fica disponível em http://localhost:8000. O site Nginx é trabalhado a partir de T3 e o HTTPS a partir de T5. Para validação TLS, segue o nome e o certificado da ficha do posto; o túnel não altera o nome incluído no certificado. O frontend Zabbix é o servidor da sala indicado em `URL_ZABBIX`.

## 6. Diagnóstico e repetição

Se uma versão anterior disser `Outro comando deste script está em execução` e `fuser -v /root/adm-srv-formador-vm/controlo.lock` mostrar apenas `kvm`, atualiza o script com o comando da secção 1 e repete `alinhar`. A versão corrigida reconhece o descritor herdado pelo QEMU e usa `controlo-v2.lock`, sem apagar o bloqueio antigo nem terminar a VM. Se identificar também um instalador ou outro processo, interrompe para evitar operações simultâneas. O novo bloqueio fica num supervisor `flock --close`, impedindo a herança por `qm`/QEMU.

No Proxmox:

```bash
bash criar-vm-formador.sh diagnostico
bash criar-vm-formador.sh retomar --espera 2400
```

`retomar` volta a enviar a preparação comum e repete-a conservando os dados. O progresso é apresentado a cada 30 segundos; os erros incluem fase, linha e código quando disponíveis, seguidos das últimas linhas do log.

Se o agente QEMU ainda não responder, usa a consola da VM:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-final.service -u adm-srv-formador.service --no-pager -n 100
sudo tail -n 100 /var/log/adm-srv-formador.log
```

Se apenas terminou a espera e a instalação continua, consulta `estado` e aguarda. Não é necessário reiniciar um processo que ainda decorre.

## 7. Validação e custódia

Conserva `/root/adm-srv-formador-vm/` no Proxmox. Na VM, conserva os ficheiros de parâmetros, as PSK, os segredos Restic, os volumes antigos e a pasta privada de migração. Não há comandos de destruir VM, apagar volumes ou repor snapshots neste script.

A validação local inclui Bash, geração cloud-init, contratos de nomes e caminhos, conservação da migração e APIs Proxmox simuladas. Não foi executada uma criação ou migração real neste ambiente.

Referências: [imagem Ubuntu 26.04](https://cloud-images.ubuntu.com/releases/resolute/release/), [Cloud-Init Proxmox](https://pve.proxmox.com/wiki/Cloud-Init_Support), [qm](https://github.com/proxmox/pve-docs/blob/master/generated/qm.1-synopsis.adoc) e [Docker em Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
