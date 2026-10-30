# Criar a VM Docker do formador no Proxmox

Este script cria uma **VM Ubuntu 26.04 LTS**, instala Docker Engine e Compose na VM e monta o [laboratório do formador](../docker-lab/README.md): CP4, Nginx com HTTPS, Restic, Zabbix e agente com PSK.

Executa-o como **root no terminal do anfitrião Proxmox**. A conta da VM será **ubuntu**, com palavra-passe **ubuntu**, conforme definido para este laboratório.

## 1. Criar

No terminal do Proxmox:

```bash
cd /root
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/Skullclamp/adm-srv/main/formador/proxmox/criar-vm-formador.sh \
  -o criar-vm-formador.sh
bash criar-vm-formador.sh criar
```

Valores iniciais:

| Parâmetro | Valor |
|---|---|
| Sistema | Ubuntu Server 26.04 LTS, imagem cloud oficial amd64 |
| Nome | `formador-docker` |
| VMID | Um ID livre, consultado no cluster Proxmox |
| CPU | 4 vCPU, tipo `host` |
| RAM | 8192 MB fixos, sem ballooning |
| Disco | 64 GB |
| Storage de discos | `local-lvm` |
| Bridge | `vmbr0`, sem VLAN |
| Rede | DHCP, incluindo DNS da rede |
| Conta na VM | `ubuntu` / `ubuntu`, com `sudo` |
| Arranque da VM | Automático com o anfitrião |

Confirma que o anfitrião tem recursos disponíveis para esta atribuição. O script precisa de acesso à Internet no Proxmox para obter a imagem e na VM para instalar pacotes, obter o repositório e descarregar as imagens Docker. Não depende dos templates nem dos VMIDs usados nos postos.

Na primeira execução, verifica o SHA256 da imagem oficial e confirma que o VMID está livre. O comando `qm create` também recusa um ID ocupado, incluindo uma atribuição concorrente. Os comandos seguintes só gerem uma VM cuja descrição corresponda ao marcador privado guardado pelo script.

Para o cloud-init, usa o storage de ficheiros `local`. Se este ainda não aceitar `snippets`, o script acrescenta esse tipo, **conservando todos os tipos já configurados**. Não instala Docker nem pacotes adicionais no Proxmox.

## 2. Alterar os valores da primeira criação

Exemplo com menos RAM, caso queiras atribuir 4096 MB:

```bash
bash criar-vm-formador.sh criar --ram 4096
```

Exemplo genérico com VMID, storage e rede escolhidos por ti; substitui os valores antes de executar:

```bash
bash criar-vm-formador.sh criar \
  --vmid VMID_LIVRE \
  --storage STORAGE_DOS_DISCOS \
  --snippets-storage STORAGE_DOS_SNIPPETS \
  --bridge BRIDGE_DA_REDE \
  --ip IP_DA_VM/PREFIXO \
  --gateway IP_DO_GATEWAY \
  --dns 'IP_DNS_1 IP_DNS_2'
```

Com IP fixo, escolhe um endereço reservado e livre na tua rede, fora de atribuições DHCP conflitantes. O script valida os endereços e a relação com o gateway; isso não comprova que outro equipamento não usa o mesmo IP. Se não indicares DNS para um IP fixo, usa `1.1.1.1 8.8.8.8`. Para uma VLAN, acrescenta `--vlan NUMERO`.

Os parâmetros ficam registados em `/root/adm-srv-formador-vm/parametros.sh`. Depois da criação, repete os comandos sem as opções iniciais. Opções diferentes das registadas são recusadas para impedir a reconfiguração acidental da VM. `--espera SEGUNDOS` pode ser ajustado em qualquer execução.

## 3. Aguardar pela preparação

O script arranca a VM e aguarda até 1800 segundos. Apresenta o progresso a cada 30 segundos. O agente QEMU permite observar o processo; o sucesso exige que a instalação termine e que o laboratório confirme HTTPS, CP4, recolha Zabbix e repositório Restic.

A preparação é iniciada por cloud-init através de um serviço `adm-srv-formador.service`. A espera não depende de tratar o código de saída de `cloud-init status` como sucesso ou falha. O script usa a lista `users` e a configuração atual de palavras-passe do cloud-init.

No final, apresenta VMID, IP, ligação SSH, túnel para o Windows e credenciais próprias do Zabbix. Estas últimas são geradas **na VM** pelo script Docker. `ubuntu` / `ubuntu` é a conta de acesso ao Ubuntu; o frontend Zabbix usa **Admin** e a palavra-passe indicada por `acessos`.

Para consultar novamente, no Proxmox:

```bash
bash criar-vm-formador.sh estado
bash criar-vm-formador.sh acessos
bash criar-vm-formador.sh verificar
```

O estado `pronto` indica que a preparação terminou anteriormente. `verificar` faz uma nova verificação dos serviços e backups em execução.

## 4. Aceder pelo Windows

No **PowerShell do Windows**, substitui `IP_DA_VM` pelo endereço apresentado:

```powershell
ssh ubuntu@IP_DA_VM
```

Noutra janela PowerShell, abre o túnel e mantém-no aberto:

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 8080:127.0.0.1:8080 -L 8443:127.0.0.1:8443 -L 8081:127.0.0.1:8081 ubuntu@IP_DA_VM
```

No browser do Windows:

- Site Nginx: <https://localhost:8443>.
- CP4: <https://localhost:8443/app/>.
- Zabbix: <http://localhost:8081>.

Segue o [guia Docker](../docker-lab/README.md#2-aceder-pelo-windows) para importar o certificado público da CA do laboratório no Windows. As portas da stack escutam em loopback na VM e são encaminhadas pelo túnel.

## 5. Diagnosticar e retomar

Se uma versão anterior terminar com `O VMID ... não corresponde à VM registada` logo após criar a VM, volta a descarregar o script pelo comando do ponto 1 e repete `criar`. A versão corrigida lê o marcador pela API JSON: a saída textual de `qm config` codifica a descrição e causava uma comparação incorreta. O estado privado existente permite retomar a mesma VM. A comparação continua a exigir o marcador exato e recusa outra VM ou um template.

Se houver uma falha de Internet ou de instalação, a VM, discos e dados ficam conservados. No Proxmox:

```bash
bash criar-vm-formador.sh diagnostico
```

Se o agente ainda não responder, abre a consola da VM no Proxmox, entra com `ubuntu` / `ubuntu` e consulta:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-final.service -u adm-srv-formador.service --no-pager -n 100
sudo tail -n 100 /var/log/adm-srv-formador.log
```

Depois de corrigir a causa, se o agente QEMU estiver disponível, volta ao Proxmox:

```bash
bash criar-vm-formador.sh retomar --espera 2400
```

Se a configuração Proxmox ainda estiver incompleta, repete `criar`. Se apenas terminou o tempo de espera e a instalação continua, consulta `estado` ou repete `criar`; não é necessário reiniciar a instalação.

Na consola da VM, também podes retomar o serviço de preparação:

```bash
sudo systemctl reset-failed adm-srv-formador.service
sudo systemctl start --no-block adm-srv-formador.service
```

Depois de pronta, uma reinicialização da VM usa o arranque automático do Docker e dos contentores. A preparação inicial não volta a instalar tudo em cada arranque. Se a VM foi reiniciada a meio da instalação, usa `retomar`.

Se introduziste uma falha didática na stack, repõe-a com o script Docker antes de repetir a preparação. Alterações locais no código do repositório são conservadas e impedem uma atualização automática desse código.

## 6. Ficheiros e validação

- No Proxmox, `/root/adm-srv-formador-vm/` guarda o VMID, marcador de propriedade e configuração privada. Conserva esta pasta para reconhecer e retomar a VM.
- A imagem verificada fica em `/var/cache/adm-srv-formador/`.
- O snippet cloud-init tem nome próprio por VM e marcador, no storage selecionado. Precisa de estar acessível no nó se migrares a VM.
- Na VM, o repositório fica em `/home/ubuntu/adm-srv`; os segredos e dados seguem o [guia Docker](../docker-lab/README.md).
- A versão inicial do laboratório está fixada no commit `b2bc4aaa6aeb802866878c4cf972b448c7caf8d4`, para que a preparação use um conjunto conhecido de ficheiros.

Não há operações de apagar VM, destruir discos ou repor snapshots neste script.

A validação desta publicação inclui sintaxe Bash, geração do cloud-init e testes locais de VMID, identidade e parâmetros. **Ainda não foi executada uma criação real no Proxmox neste ambiente.** Na máquina de preparação não existe um anfitrião Proxmox nem Docker. O script verifica o resultado dentro da VM quando é executado.

Referências: [imagem oficial Ubuntu 26.04 LTS](https://cloud-images.ubuntu.com/releases/resolute/release/), [Cloud-Init no Proxmox](https://pve.proxmox.com/wiki/Cloud-Init_Support), [comandos qm](https://github.com/proxmox/pve-docs/blob/master/generated/qm.1-synopsis.adoc), [instalação oficial Docker em Ubuntu](https://docs.docker.com/engine/install/ubuntu/) e [contas cloud-init](https://docs.cloud-init.io/en/latest/reference/modules.html#users-and-groups).
