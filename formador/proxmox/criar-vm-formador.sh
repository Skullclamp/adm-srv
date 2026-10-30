#!/usr/bin/env bash
# Executar como root no anfitrião Proxmox VE. Instala Docker apenas na VM nova.
set -Eeuo pipefail

STATE_DIR=/root/adm-srv-formador-vm
CACHE_DIR=/var/cache/adm-srv-formador
STATE_FILE="$STATE_DIR/parametros.sh"
IMAGE_NAME=ubuntu-26.04-server-cloudimg-amd64.img
IMAGE_BASE=https://cloud-images.ubuntu.com/releases/resolute/release
VMID=auto
NOME=formador-docker
STORAGE=local-lvm
SNIPPETS_STORAGE=local
BRIDGE=vmbr0
VLAN=
IP=dhcp
GATEWAY=
DNS=
CORES=4
RAM=8192
DISCO=64
ESPERA=1800
LAB_REF=8ebce3b45c866382669d0737044435febb42a4d3
# Atualizado na publicação do ambiente comum; marcador de versão para a migração.
REF_COMUM=8ebce3b45c866382669d0737044435febb42a4d3
POSTO=formador
IP_ZABBIX=
CA_ORIGEM=/root/laboratorio/segredos/ca-lab.crt
TOKEN=
NODE=
STATE_KEYS=(VMID NOME STORAGE SNIPPETS_STORAGE BRIDGE VLAN IP GATEWAY DNS CORES RAM DISCO LAB_REF TOKEN NODE POSTO IP_ZABBIX CA_ORIGEM)
declare -A PEDIDOS=()

erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
msg() { printf '\n==> %s\n' "$*"; }

ajuda() {
    cat <<'TXT'
Uso no Proxmox, como root:
  bash criar-vm-formador.sh criar [opções]
  bash criar-vm-formador.sh estado | acessos | diagnostico | alinhar | retomar | verificar

Opções da primeira criação:
  --vmid NUMERO           por omissão: VMID livre atribuído pelo Proxmox
  --nome NOME             formador-docker
  --storage STORAGE       local-lvm; tem de aceitar discos de VM
  --snippets-storage ID   local; armazenamento de ficheiros cloud-init
  --bridge BRIDGE         vmbr0
  --vlan NUMERO           sem tag por omissão
  --ip ENDERECO/CIDR      DHCP por omissão
  --gateway ENDERECO      obrigatório com IP fixo
  --dns 'IP1 IP2'         DHCP: DNS da rede; IP fixo: 1.1.1.1 8.8.8.8
  --cores NUMERO          4
  --ram MB               8192; mínimo 4096
  --disco GB             64; mínimo 32
  --espera SEGUNDOS      1800; também aceite nos comandos seguintes
  --posto ID             formador; usa a mesma regra de caminhos dos postos p1, p2…
  --ip-zabbix IP         servidor da sala; lê lab.conf privado quando disponível
  --ca-cert FICHEIRO     certificado público da CA da sala

Ubuntu 26.04 LTS, conta ubuntu / ubuntu e preparação igual à dos formandos.
CP4: ~/cp4, projeto cp4, serviço app, volume cp4_dados, /dados e porta 8000.
Nginx, Restic e Agent 2 nativos; backup num disco adicional de 10 GB.
alinhar adapta a VM antiga, guardando configurações e volumes. Pode reiniciá-la.
Repetir criar retoma a mesma VM identificada pelo estado privado, sem criar outra.
Não há comando de remoção ou reposição de discos neste script.
TXT
}

argumentos() {
    COMANDO=${1:-criar}
    [[ $# -eq 0 ]] || shift
    local chave
    while (($#)); do
        [[ $# -ge 2 && -n "$2" ]] || erro "Falta o valor de $1"
        case "$1" in
            --vmid) chave=VMID ;; --nome) chave=NOME ;; --storage) chave=STORAGE ;;
            --snippets-storage) chave=SNIPPETS_STORAGE ;; --bridge) chave=BRIDGE ;;
            --vlan) chave=VLAN ;; --ip) chave=IP ;; --gateway) chave=GATEWAY ;;
            --dns) chave=DNS ;; --cores) chave=CORES ;; --ram) chave=RAM ;;
            --disco) chave=DISCO ;; --espera) chave=ESPERA ;;
            --posto) chave=POSTO ;; --ip-zabbix) chave=IP_ZABBIX ;; --ca-cert) chave=CA_ORIGEM ;;
            *) erro "Opção desconhecida: $1" ;;
        esac
        printf -v "$chave" '%s' "$2"
        [[ "$chave" == ESPERA ]] || PEDIDOS["$chave"]=$2
        shift 2
    done
}

dependencias() {
    [[ $EUID -eq 0 && -d /etc/pve ]] || erro 'Executar como root no anfitrião Proxmox VE.'
    local ferramenta
    for ferramenta in qm pvesh pvesm curl openssl sha256sum python3 flock ip; do
        command -v "$ferramenta" >/dev/null || erro "Falta a ferramenta $ferramenta no Proxmox."
    done
    [[ $(uname -m) == x86_64 ]] || erro 'Esta imagem é para um anfitrião x86_64.'
    [[ ! -L "$STATE_DIR" ]] || erro 'A pasta de estado não pode ser uma ligação simbólica.'
    install -d -m 0700 "$STATE_DIR"
    [[ ! -L "$STATE_DIR/controlo.lock" && ! -L "$STATE_DIR/controlo-v2.lock" ]] || erro 'O bloqueio não pode ser uma ligação simbólica.'
}

verificar_bloqueio_herdado() {
    python3 - "$STATE_DIR/controlo.lock" <<'PY_LOCK'
import os
from pathlib import Path
import sys

def titulares(lock_path, proc_root=Path('/proc')):
    target = os.stat(lock_path)
    found = []
    for process in proc_root.iterdir():
        if not process.name.isdecimal():
            continue
        try:
            for descriptor in (process / 'fd').iterdir():
                try:
                    opened = descriptor.stat()
                except FileNotFoundError:
                    continue
                if (opened.st_dev, opened.st_ino) == (target.st_dev, target.st_ino):
                    executable = Path(os.readlink(process / 'exe')).name
                    found.append((int(process.name), executable))
                    break
        except (FileNotFoundError, ProcessLookupError):
            continue
    return found

def validar(found):
    # O nome do executável é verificado, não apenas o nome visível do processo.
    qemu = {'kvm', 'qemu-system-x86_64'}
    if not found or any(executable not in qemu for _, executable in found):
        details = ', '.join(f'{pid} ({exe})' for pid, exe in found) or 'titular não identificado'
        raise RuntimeError('O bloqueio antigo ainda tem uma operação ativa ou desconhecida: ' + details)

if __name__ == '__main__':
    try:
        found = titulares(sys.argv[1])
        validar(found)
    except (OSError, RuntimeError) as exc:
        raise SystemExit('ERRO: ' + str(exc) + '. Nenhum processo foi terminado; voltar a tentar depois de concluir a operação.')
    print('Bloqueio antigo herdado apenas pelo QEMU; a VM continua em execução. A usar o bloqueio corrigido.')
PY_LOCK
}

com_bloqueio_antigo() {
    local codigo=0
    # Quando está livre, também protegemos contra uma execução da versão antiga.
    flock --nonblock --conflict-exit-code 200 --close "$STATE_DIR/controlo.lock" \
        /bin/bash -c 'source "$1"; shift; main_bloqueado "$@"' "$0" "${BASH_SOURCE[0]}" "$@" || codigo=$?
    if [[ $codigo -eq 200 ]]; then
        verificar_bloqueio_herdado
        main_bloqueado "$@"
    else
        return "$codigo"
    fi
}

com_bloqueio() {
    local codigo=0
    # flock mantém o bloqueio no processo supervisor. --close impede que qm/kvm
    # recebam o descritor e conservem o bloqueio depois de o script terminar.
    # O ficheiro antigo não é apagado nem desbloqueado à força.
    flock --nonblock --conflict-exit-code 200 --close "$STATE_DIR/controlo-v2.lock" \
        /bin/bash -c 'source "$1"; shift; com_bloqueio_antigo "$@"' "$0" "${BASH_SOURCE[0]}" "$@" || codigo=$?
    [[ $codigo -ne 200 ]] || erro 'Outro comando deste script está em execução.'
    return "$codigo"
}

guardar_estado() {
    local chave
    {
        printf '# Estado privado da VM; gerado pelo script. Não publicar.\n'
        for chave in "${STATE_KEYS[@]}"; do printf '%s=%q\n' "$chave" "${!chave}"; done
    } > "$STATE_FILE.novo"
    chmod 0600 "$STATE_FILE.novo"
    mv -- "$STATE_FILE.novo" "$STATE_FILE"
}

carregar_estado() {
    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" && -O "$STATE_FILE" ]] || erro 'Não existe um estado privado válido desta VM.'
    # Ficheiro privado gerado por guardar_estado, com valores escapados por printf %q.
    source "$STATE_FILE"
    local chave
    for chave in "${!PEDIDOS[@]}"; do
        [[ "${!chave}" == "${PEDIDOS[$chave]}" ]] || erro "A VM já está registada com outro valor de $chave. Não alterar a VM existente automaticamente."
    done
    [[ "$NODE" == "$(hostname -s)" ]] || erro "O estado pertence ao nó $NODE. Executar nesse nó."
}

validar_opcoes() {
    python3 - "$VMID" "$NOME" "$STORAGE" "$SNIPPETS_STORAGE" "$BRIDGE" "$VLAN" \
        "$IP" "$GATEWAY" "$DNS" "$CORES" "$RAM" "$DISCO" "$ESPERA" "$LAB_REF" <<'PY_VALIDAR'
import ipaddress, re, sys
vmid, name, storage, snippets, bridge, vlan, address, gateway, dns, cores, ram, disk, wait, ref = sys.argv[1:]
def require(condition, message):
    if not condition:
        raise SystemExit('ERRO: ' + message)
def integer(value, lower, upper, label):
    require(bool(re.fullmatch(r'[1-9][0-9]*', value)), label + ' deve ser um inteiro positivo.')
    require(lower <= int(value) <= upper, label + ' fora dos limites permitidos.')
if vmid != 'auto':
    integer(vmid, 100, 999999999, 'VMID')
require(bool(re.fullmatch(r'[a-zA-Z][a-zA-Z0-9-]{0,62}', name)), 'Nome de VM inválido.')
for value in (storage, snippets, bridge):
    require(bool(re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}', value)), 'Storage ou bridge inválidos.')
if vlan:
    integer(vlan, 1, 4094, 'VLAN')
integer(cores, 2, 128, 'CORES')
integer(ram, 4096, 1048576, 'RAM')
integer(disk, 32, 1048576, 'DISCO')
integer(wait, 30, 86400, 'ESPERA')
require(bool(re.fullmatch(r'[0-9a-f]{40}', ref)), 'Referência Git inválida.')
try:
    if address == 'dhcp':
        require(not gateway, 'Não indicar gateway com DHCP.')
    else:
        require('/' in address and bool(gateway), 'IP fixo exige CIDR e --gateway.')
        interface = ipaddress.IPv4Interface(address)
        gw = ipaddress.IPv4Address(gateway)
        require(1 <= interface.network.prefixlen <= 30, 'Prefixo IPv4 deve ficar entre 1 e 30.')
        require(interface.ip not in (interface.network.network_address, interface.network.broadcast_address), 'IP de rede ou broadcast não permitido.')
        require(gw in interface.network and gw != interface.ip, 'Gateway deve pertencer à rede e ser diferente da VM.')
        require(gw not in (interface.network.network_address, interface.network.broadcast_address), 'Gateway de rede ou broadcast não permitido.')
    for server in dns.split():
        ipaddress.ip_address(server)
except ValueError as exc:
    raise SystemExit('ERRO: Parâmetro de rede inválido: ' + str(exc))
PY_VALIDAR
}

verificar_identidade() {
    local config
    [[ "$TOKEN" =~ ^[0-9a-f]{32}$ ]] || erro 'Marcador privado inválido.'
    # qm config codifica a descrição na saída textual. A API JSON preserva o valor.
    config=$(pvesh get "/nodes/$NODE/qemu/$VMID/config" --current 1 --output-format json) \
        || erro "A VM $VMID não está disponível neste nó; o estado foi conservado."
    printf '%s' "$config" | python3 -c '
import json, sys
token, vmid = sys.argv[1:]
try:
    config = json.load(sys.stdin)
except (ValueError, TypeError):
    raise SystemExit("ERRO: A API não devolveu uma configuração JSON válida. A VM não foi alterada.")
if not isinstance(config, dict) or config.get("description") != "adm-srv-formador:" + token:
    raise SystemExit(f"ERRO: O VMID {vmid} não corresponde à VM registada. Não foi alterado.")
if str(config.get("template", 0)).lower() in ("1", "true"):
    raise SystemExit("ERRO: O VMID é um template; recusar a alteração.")' "$TOKEN" "$VMID"
}

escolher_vmid() {
    if [[ "$VMID" == auto ]]; then VMID=$(pvesh get /cluster/nextid --output-format json | tr -d '"[:space:]'); fi
    [[ "$VMID" =~ ^[1-9][0-9]*$ ]] && ((VMID >= 100 && VMID <= 999999999)) || erro 'A API não devolveu um VMID válido.'
    pvesh get /cluster/nextid --vmid "$VMID" >/dev/null || erro "O VMID $VMID já está ocupado no cluster. Escolher outro."
}

parametros_sala() {
    if [[ -z "$IP_ZABBIX" && -f /root/laboratorio/lab.conf ]]; then
        IP_ZABBIX=$(python3 - /root/laboratorio/lab.conf <<'PY_SALA'
import shlex, sys
from pathlib import Path
for line in Path(sys.argv[1]).read_text().splitlines():
    words=shlex.split(line, comments=True)
    if words and words[0].startswith('IP_ZABBIX='):
        print(words[0].split('=',1)[1]); break
PY_SALA
)
    fi
    [[ "$POSTO" =~ ^[a-zA-Z0-9_-]+$ ]] || erro 'Identificador do posto inválido.'
    [[ -n "$IP_ZABBIX" ]] || erro 'Indicar --ip-zabbix com o servidor da sala, ou disponibilizar /root/laboratorio/lab.conf.'
    python3 -c 'import ipaddress,sys;ipaddress.IPv4Address(sys.argv[1])' "$IP_ZABBIX"
    [[ -f "$CA_ORIGEM" ]] || erro 'Indicar --ca-cert com o certificado público da CA da sala.'
    openssl x509 -in "$CA_ORIGEM" -noout >/dev/null
    ! grep -q 'PRIVATE KEY' "$CA_ORIGEM" || erro 'Fornecer apenas o certificado público da CA.'
}

disco_backup_vm() {
    local config ligado
    config=$(qm config "$VMID")
    if grep -q '^scsi1:' <<< "$config"; then
        grep '^scsi1:' <<< "$config" | grep -Eq "(^|,)serial=lab-backup-$VMID(,|$)" \
            || erro 'scsi1 já está ocupado por outro disco. Rever o disco de backup sem o substituir.'
        return 0
    fi
    ligado=$(qm status "$VMID")
    qm set "$VMID" --scsi1 "$STORAGE:10,serial=lab-backup-$VMID"
    if [[ "$ligado" == 'status: running' ]]; then
        msg 'A reiniciar a VM para reconhecer o novo disco de backup'
        qm reboot "$VMID" --timeout 120
        sleep 10
    fi
}

aguardar_agente() {
    local limite=$((SECONDS + 300))
    while ((SECONDS < limite)); do
        if qm guest cmd "$VMID" ping >/dev/null 2>&1; then return 0; fi
        sleep 5
    done
    erro 'O agente QEMU ainda não responde. Consultar a consola da VM antes de repetir alinhar.'
}

storage_config() { pvesh get "/storage/$1" --output-format json; }

validar_infraestrutura() {
    ip link show dev "$BRIDGE" >/dev/null || erro "A bridge $BRIDGE não existe."
    [[ -d "/sys/class/net/$BRIDGE/bridge" ]] || erro 'Este script requer uma bridge Linux.'
    storage_config "$STORAGE" | python3 -c '
import json, sys
c=json.load(sys.stdin)
if c.get("disable") or "images" not in c.get("content", "").split(","):
    raise SystemExit("ERRO: O storage de discos está desativado ou não aceita images.")'
    pvesm status --storage "$STORAGE" | awk 'NR>1 && $3=="active" {ok=1} END {exit !ok}' \
        || erro "Storage $STORAGE inativo neste nó."
    storage_config "$SNIPPETS_STORAGE" | python3 -c '
import json, sys
c=json.load(sys.stdin)
if c.get("disable") or c.get("type") not in ("dir", "nfs", "cifs", "cephfs"):
    raise SystemExit("ERRO: O storage de snippets deve ser de ficheiros e estar ativo.")'
    pvesm status --storage "$SNIPPETS_STORAGE" | awk 'NR>1 && $3=="active" {ok=1} END {exit !ok}' \
        || erro "Storage $SNIPPETS_STORAGE inativo neste nó."
}

obter_imagem() {
    install -d -m 0700 "$CACHE_DIR"
    local esperado atual=
    curl --fail --silent --show-error --location --retry 3 "$IMAGE_BASE/SHA256SUMS" -o "$CACHE_DIR/SHA256SUMS"
    esperado=$(awk -v nome="$IMAGE_NAME" '$2=="*"nome || $2==nome {print $1}' "$CACHE_DIR/SHA256SUMS")
    [[ "$esperado" =~ ^[0-9a-f]{64}$ ]] || erro 'Não foi encontrado um SHA256 único para a imagem Ubuntu 26.04.'
    IMAGE="$CACHE_DIR/$IMAGE_NAME"
    [[ ! -f "$IMAGE" ]] || atual=$(sha256sum "$IMAGE" | awk '{print $1}')
    if [[ "$atual" != "$esperado" ]]; then
        msg 'A descarregar a imagem oficial Ubuntu 26.04 LTS'
        curl --fail --location --retry 3 --progress-bar "$IMAGE_BASE/$IMAGE_NAME" -o "$IMAGE.part"
        atual=$(sha256sum "$IMAGE.part" | awk '{print $1}')
        [[ "$atual" == "$esperado" ]] || erro 'SHA256 incorreto. A imagem não foi importada; repetir criar.'
        mv -- "$IMAGE.part" "$IMAGE"
    fi
    printf 'Imagem verificada: %s\n' "$esperado"
}

bootstrap_guest() {
    cat <<'BASH_GUEST'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
STATE=/var/lib/adm-srv-formador
REPO=/home/ubuntu/adm-srv
URL=https://github.com/Skullclamp/adm-srv.git
install -d -m 0700 "$STATE"
exec 9>/run/lock/adm-srv-formador.lock
flock -n 9 || { echo 'Já existe uma preparação em execução.' >&2; exit 1; }
exec > >(tee -a /var/log/adm-srv-formador.log) 2>&1
FASE=docker
LINHA_ERRO=desconhecida
trap 'LINHA_ERRO=$LINENO' ERR
trap 'rc=$?; if ((rc != 0)); then printf "erro-%s-linha-%s-codigo-%s\n" "$FASE" "$LINHA_ERRO" "$rc" > "$STATE/estado"; echo "Preparação interrompida na fase $FASE; consultar /var/log/adm-srv-formador.log." >&2; fi; exit "$rc"' EXIT
printf 'a-instalar-docker\n' > "$STATE/estado"
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 && $(dpkg --print-architecture) == amd64 ]]
LAB_REF=$(cat /etc/adm-srv-formador-ref)
[[ "$LAB_REF" =~ ^[0-9a-f]{40}$ ]]

# A VM é nova. Uma instalação conflitante acrescentada posteriormente exige revisão.
for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if [[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true) == installed ]]; then
        echo "Pacote conflitante na VM: $package. Rever antes de retomar." >&2
        exit 1
    fi
done
install -d -m 0755 /etc/apt/keyrings
curl --fail --silent --show-error --location --retry 3 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker compose version

FASE=repositorio
printf 'a-obter-material-comum\n' > "$STATE/estado"
if [[ ! -e "$REPO" ]]; then
    runuser -u ubuntu -- git clone "$URL" "$REPO"
fi
[[ -d "$REPO/.git" && ! -L "$REPO" ]] || { echo 'A pasta de destino já existe sem um repositório válido.' >&2; exit 1; }
git_ubuntu() { runuser -u ubuntu -- git -C "$REPO" "$@"; }
[[ $(git_ubuntu remote get-url origin) == "$URL" ]]
[[ -z $(git_ubuntu status --porcelain) ]] || { echo 'Existem alterações locais; conservadas. Rever antes de retomar.' >&2; exit 1; }
git_ubuntu fetch --depth 1 origin "$LAB_REF"
git_ubuntu checkout --detach "$LAB_REF"
FASE=posto
printf 'a-preparar-posto-comum\n' > "$STATE/estado"
mapfile -t OPCOES < <(python3 -c 'import json; c=json.load(open("/etc/adm-srv-formador-opcoes.json")); print(c["posto"]);print(c["ip_zabbix"]);print(c["disco_serial"])')
[[ ${#OPCOES[@]} -eq 3 ]]
bash "$REPO/preparar-posto.sh" instalar --posto "${OPCOES[0]}" --ip-zabbix "${OPCOES[1]}" \
    --ca-cert /root/ca-lab.crt --disco-serial "${OPCOES[2]}" --inicializar-disco --migrar-docker
printf 'pronto\n' > "$STATE/estado"
printf '%s\n' "$LAB_REF" > "$STATE/pronto"
echo 'VM do formador preparada com o mesmo modelo dos formandos. Continuar T0–T17.'
BASH_GUEST
}

criar_snippet() {
    local conteudos destino hash
    conteudos=$(storage_config "$SNIPPETS_STORAGE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", ""))')
    if [[ ",$conteudos," != *",snippets,"* ]]; then
        msg "A acrescentar snippets ao storage $SNIPPETS_STORAGE, mantendo os tipos existentes"
        pvesm set "$SNIPPETS_STORAGE" --content "${conteudos:+$conteudos,}snippets"
    fi
    SNIPPET_VOLUME="$SNIPPETS_STORAGE:snippets/adm-srv-formador-$VMID-$TOKEN.yaml"
    destino=$(pvesm path "$SNIPPET_VOLUME")
    [[ ! -L "$destino" ]] || erro 'O destino do snippet não pode ser uma ligação simbólica.'
    install -d -m 0755 "$(dirname -- "$destino")"
    bootstrap_guest > "$STATE_DIR/bootstrap-guest.sh"
    hash=$(printf '%s' ubuntu | openssl passwd -6 -stdin)
    python3 - "$NOME" "$hash" "$LAB_REF" "$STATE_DIR/bootstrap-guest.sh" "$POSTO" "$IP_ZABBIX" "$CA_ORIGEM" "lab-backup-$VMID" > "$STATE_DIR/cloud-init.yaml" <<'PY_CLOUD'
import json, pathlib, sys
name, password_hash, ref, guest, posto, zabbix, ca, serial = sys.argv[1:]
unit = '''[Unit]
Description=Preparar laboratorio Docker do formador
Wants=network-online.target
After=network-online.target cloud-final.service
ConditionPathExists=!/var/lib/adm-srv-formador/pronto

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/preparar-formador-docker
RemainAfterExit=yes
TimeoutStartSec=0
'''
config = {
    'hostname': name, 'manage_etc_hosts': True, 'timezone': 'Europe/Lisbon',
    'disable_root': True, 'ssh_pwauth': True,
    'users': [{'name': 'ubuntu', 'gecos': 'Formador', 'shell': '/bin/bash',
               'groups': ['adm', 'sudo'], 'sudo': 'ALL=(ALL) NOPASSWD:ALL',
               'lock_passwd': False, 'hashed_passwd': password_hash}],
    'chpasswd': {'expire': False}, 'package_update': True,
    'packages': ['qemu-guest-agent', 'openssh-server', 'ca-certificates', 'curl', 'git', 'openssl', 'util-linux'],
    'write_files': [
        {'path': '/usr/local/sbin/preparar-formador-docker', 'owner': 'root:root', 'permissions': '0700',
         'content': pathlib.Path(guest).read_text(encoding='utf-8')},
        {'path': '/etc/adm-srv-formador-ref', 'owner': 'root:root', 'permissions': '0600', 'content': ref + '\n'},
        {'path': '/etc/adm-srv-formador-opcoes.json', 'owner': 'root:root', 'permissions': '0600',
         'content': json.dumps({'posto':posto, 'ip_zabbix':zabbix, 'disco_serial':serial})},
        {'path': '/root/ca-lab.crt', 'owner': 'root:root', 'permissions': '0644', 'content': pathlib.Path(ca).read_text()},
        {'path': '/etc/ssh/sshd_config.d/00-formador.conf', 'owner': 'root:root', 'permissions': '0644',
         'content': 'PasswordAuthentication yes\nPermitRootLogin no\n'},
        {'path': '/etc/systemd/system/adm-srv-formador.service', 'owner': 'root:root', 'permissions': '0644', 'content': unit},
    ],
    'runcmd': [
        ['systemctl', 'start', 'qemu-guest-agent'], ['systemctl', 'restart', 'ssh'],
        ['systemctl', 'daemon-reload'],
        ['systemctl', 'start', '--no-block', 'adm-srv-formador.service'],
    ],
}
# JSON é um subconjunto de YAML: não requer PyYAML instalado no Proxmox.
print('#cloud-config')
print(json.dumps(config, ensure_ascii=False, indent=2))
PY_CLOUD
    install -m 0600 "$STATE_DIR/cloud-init.yaml" "$destino"
}

configurar_vm() {
    local config rede disco rede_ip
    verificar_identidade
    [[ ! -f "$STATE_DIR/vm-configurada" ]] || return 0
    [[ $(qm status "$VMID") == 'status: stopped' ]] || erro 'A configuração inicial está incompleta, mas a VM está ligada. Rever antes de prosseguir.'
    config=$(qm config "$VMID")
    if ! grep -q '^scsi0:' <<< "$config"; then
        ! grep -Eq '^unused[0-9]+:' <<< "$config" || erro 'Há um disco importado sem ligação. Rever qm config antes de repetir; não será criado outro disco.'
        obter_imagem
        qm set "$VMID" --scsi0 "$STORAGE:0,import-from=$IMAGE,discard=on"
    fi
    disco=$(qm config "$VMID" | sed -n 's/^scsi0: //p')
    [[ "$disco" == "$STORAGE:"* && "$disco" == *"vm-$VMID-"* ]] || erro 'O disco de arranque não corresponde ao disco esperado desta VM.'
    if [[ ",$disco," != *",size=${DISCO}G,"* ]]; then qm resize "$VMID" scsi0 "${DISCO}G"; fi
    if ! qm config "$VMID" | grep -q '^ide2:'; then qm set "$VMID" --ide2 "$STORAGE:cloudinit"; fi
    qm config "$VMID" | grep -Eq '^ide2: .*cloudinit' || erro 'O dispositivo ide2 existente não é cloud-init.'
    criar_snippet
    rede="virtio,bridge=$BRIDGE${VLAN:+,tag=$VLAN}"
    rede_ip="ip=$IP"
    [[ "$IP" == dhcp ]] || rede_ip+=",gw=$GATEWAY"
    local dns_args=()
    [[ -z "$DNS" ]] || dns_args=(--nameserver "$DNS")
    qm set "$VMID" --name "$NOME" --cores "$CORES" --memory "$RAM" --balloon 0 \
        --cpu host --net0 "$rede" --ostype l26 --scsihw virtio-scsi-single \
        --boot order=scsi0 --serial0 socket --vga serial0 --agent enabled=1 --onboot 1 \
        --ciuser ubuntu --ipconfig0 "$rede_ip" "${dns_args[@]}" --cicustom "user=$SNIPPET_VOLUME"
    qm cloudinit update "$VMID"
    disco_backup_vm
    touch "$STATE_DIR/vm-configurada"
    touch "$STATE_DIR/preparacao-comum"
}

enviar_preparacao() {
    bootstrap_guest > "$STATE_DIR/bootstrap-guest.sh"
    python3 - "$STATE_DIR/bootstrap-guest.sh" "$LAB_REF" "$POSTO" "$IP_ZABBIX" "$CA_ORIGEM" "lab-backup-$VMID" > "$STATE_DIR/atualizar-guest.json" <<'PY_ENVIO'
import json, pathlib, sys
script, ref, posto, server, ca, serial=sys.argv[1:]
print(json.dumps({
 '/usr/local/sbin/preparar-formador-docker': [0o700,pathlib.Path(script).read_text()],
 '/etc/adm-srv-formador-ref': [0o600,ref+'\n'],
 '/etc/adm-srv-formador-opcoes.json': [0o600,json.dumps({'posto':posto,'ip_zabbix':server,'disco_serial':serial})],
 '/root/ca-lab.crt': [0o644,pathlib.Path(ca).read_text()],
}))
PY_ENVIO
    local resultado
    resultado=$(qm guest exec "$VMID" --timeout 30 --synchronous 1 --pass-stdin 1 -- /usr/bin/python3 -c '
import json, os, pathlib, sys
allowed={"/usr/local/sbin/preparar-formador-docker","/etc/adm-srv-formador-ref","/etc/adm-srv-formador-opcoes.json","/root/ca-lab.crt"}
files=json.load(sys.stdin)
if set(files)!=allowed:
    raise SystemExit("Lista de ficheiros inesperada; não aplicada.")
for name,(mode,content) in files.items():
    path=pathlib.Path(name)
    if path.is_symlink():
        raise SystemExit("Destino inesperado; não aplicado.")
    path.write_text(content)
    path.chmod(mode)
print("Preparação comum atualizada; dados e volumes conservados.")' < "$STATE_DIR/atualizar-guest.json")
    resultado_guest "$resultado"
}

alinhar_vm() {
    parametros_sala
    LAB_REF=$REF_COMUM
    guardar_estado
    [[ $(qm status "$VMID") == 'status: running' ]] || qm start "$VMID"
    disco_backup_vm
    aguardar_agente
    guest 120 'set -e; systemctl stop adm-srv-formador.service; if test -f /var/lib/adm-srv-formador/pronto; then cp -a /var/lib/adm-srv-formador/pronto /var/lib/adm-srv-formador/pronto-anterior; fi'
    enviar_preparacao
    touch "$STATE_DIR/preparacao-comum"
    guest 20 'set -e; systemctl daemon-reload; systemctl reset-failed adm-srv-formador.service; install -d -m 0700 /var/lib/adm-srv-formador; rm -f /var/lib/adm-srv-formador/pronto; printf "a-alinhar\n" > /var/lib/adm-srv-formador/estado; systemctl restart --no-block adm-srv-formador.service'
    aguardar
    acessos
}

resultado_guest() {
    printf '%s' "$1" | python3 -c '
import json, sys
r=json.load(sys.stdin)
sys.stdout.write(r.get("out-data", ""))
if not r.get("exited"):
    raise SystemExit("O comando ainda decorre na VM; consultar diagnostico.")
if r.get("exitcode", 1):
    sys.stderr.write(r.get("err-data", ""))
    sys.exit(r.get("exitcode", 1))'
}

guest() {
    local limite=$1 comando=$2 raw
    raw=$(qm guest exec "$VMID" --timeout "$limite" --synchronous 1 -- /bin/bash -lc "$comando") || return "$?"
    resultado_guest "$raw"
}

ip_vm() {
    qm guest cmd "$VMID" network-get-interfaces | python3 -c '
import ipaddress, json, sys
for interface in json.load(sys.stdin):
    for item in interface.get("ip-addresses", []):
        if item.get("ip-address-type") != "ipv4":
            continue
        address=ipaddress.ip_address(item["ip-address"])
        if not address.is_loopback and not address.is_link_local and interface.get("name") not in ("docker0",) and not interface.get("name", "").startswith(("veth", "br-")):
            print(address)
            sys.exit(0)
sys.exit(1)'
}

aguardar() {
    local limite=$((SECONDS + ESPERA)) estado=a-aguardar-agente anuncio=0
    while ((SECONDS < limite)); do
        if qm guest cmd "$VMID" ping >/dev/null 2>&1; then
            estado=$(guest 10 'cat /var/lib/adm-srv-formador/estado 2>/dev/null || echo a-aguardar-cloud-init' 2>/dev/null) || estado=a-aguardar-preparacao
            case "$estado" in
                pronto) msg 'Preparação comum concluída; continuar os exercícios pelo mesmo guia'; return 0 ;;
                erro-*) guest 20 'tail -n 70 /var/log/adm-srv-formador.log' || true; erro "A preparação da VM falhou ($estado). Executar: bash $0 diagnostico; depois de corrigir, usar retomar." ;;
            esac
        fi
        if ((SECONDS >= anuncio)); then printf 'VM %s: %s\n' "$VMID" "$estado"; anuncio=$((SECONDS + 30)); fi
        sleep 10
    done
    erro "Tempo de espera terminado. A VM $VMID foi conservada e pode continuar a preparar. Consultar estado/diagnostico e repetir criar."
}

acessos() {
    local endereco
    endereco=$(ip_vm 2>/dev/null) || endereco=IP_DA_VM
    printf '\nVMID: %s\nNome: %s\nIP: %s\nSSH: ssh ubuntu@%s\nConta Ubuntu: ubuntu / ubuntu\n' "$VMID" "$NOME" "$endereco" "$endereco"
    printf '\nNo PowerShell do Windows, manter o túnel aberto:\n'
    printf 'ssh -N -o ExitOnForwardFailure=yes -L 8000:127.0.0.1:8000 -L 8080:127.0.0.1:80 -L 8443:127.0.0.1:443 ubuntu@%s\n' "$endereco"
    guest 20 'source /home/ubuntu/parametros-posto.sh; printf "\nCP4: ~/cp4/compose.yaml | projeto cp4 | serviço app | volume cp4_dados\nAmostra T1: %s\nSite do posto: %s\nZabbix da sala: %s\nNa shell Ubuntu: source ~/parametros-posto.sh\n" "$AMOSTRA_ORIGEM" "$NOME_SITE" "$URL_ZABBIX"'
}

main_bloqueado() {
    case "${1:-}" in ajuda|help|-h|--help) ajuda; return 0 ;; esac
    argumentos "$@"
    case "$COMANDO" in criar|estado|acessos|diagnostico|alinhar|retomar|verificar) ;; *) erro 'Comando desconhecido. Consultar ajuda.' ;; esac
    trap 'printf "Operação interrompida na linha %s; VM, discos e estado foram conservados.\n" "$LINENO" >&2' ERR
    umask 077
    if [[ -f "$STATE_FILE" ]]; then
        carregar_estado
    else
        [[ "$COMANDO" == criar ]] || erro 'Ainda não existe uma VM registada. Executar criar.'
        NODE=$(hostname -s)
        TOKEN=$(openssl rand -hex 16)
    fi
    [[ "$IP" == dhcp || -n "$DNS" ]] || DNS='1.1.1.1 8.8.8.8'
    validar_opcoes
    if [[ "$COMANDO" == criar ]]; then
        parametros_sala
        LAB_REF=$REF_COMUM
        if [[ -f "$STATE_FILE" && -f "$STATE_DIR/vm-configurada" && ! -f "$STATE_DIR/preparacao-comum" ]]; then
            verificar_identidade
            alinhar_vm
            return 0
        fi
        validar_infraestrutura
        if [[ ! -f "$STATE_FILE" ]]; then
            escolher_vmid
            validar_opcoes
            obter_imagem
            guardar_estado
        fi
        guardar_estado
        if ! qm status "$VMID" >/dev/null 2>&1; then
            [[ ! -f "$STATE_DIR/vm-configurada" ]] || erro 'A VM registada deixou de existir. Não será recriada sobre o estado anterior.'
            pvesh get /cluster/nextid --vmid "$VMID" >/dev/null || erro "VMID $VMID ocupado; nenhuma VM foi alterada."
            msg "A criar VM $VMID — $NOME, Ubuntu 26.04, $CORES vCPU, $RAM MB, ${DISCO} GB"
            qm create "$VMID" --name "$NOME" --description "adm-srv-formador:$TOKEN" --tags adm-srv-formador \
                --memory "$RAM" --balloon 0 --cores "$CORES" --scsihw virtio-scsi-single
        fi
        configurar_vm
        [[ $(qm status "$VMID") == 'status: running' ]] || qm start "$VMID"
        aguardar
        acessos
        return 0
    fi
    verificar_identidade
    case "$COMANDO" in
        estado)
            qm status "$VMID"
            printf 'VMID: %s | %s | Ubuntu 26.04 LTS\n' "$VMID" "$NOME"
            ip_vm 2>/dev/null || true
            guest 10 'cat /var/lib/adm-srv-formador/estado 2>/dev/null || echo a-aguardar-cloud-init' || true
            ;;
        acessos) acessos ;;
        diagnostico)
            qm status "$VMID"
            guest 20 'cloud-init status --long; systemctl --no-pager --full status adm-srv-formador.service || true; journalctl -u cloud-final.service -u adm-srv-formador.service --no-pager -n 70; tail -n 70 /var/log/adm-srv-formador.log 2>/dev/null || true'
            ;;
        alinhar|retomar)
            [[ -f "$STATE_DIR/vm-configurada" ]] || erro 'Configuração Proxmox incompleta; repetir criar.'
            alinhar_vm
            ;;
        verificar) guest 600 'bash /home/ubuntu/adm-srv/preparar-posto.sh verificar' ;;
    esac
}

main() {
    case "${1:-}" in ajuda|help|-h|--help) ajuda; return 0 ;; esac
    umask 077
    dependencias
    com_bloqueio "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
