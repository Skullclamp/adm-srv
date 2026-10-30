#!/usr/bin/env bash
# Executar na VM Ubuntu 26.04. Não utiliza o agente QEMU.
set -Eeuo pipefail

VERSAO_MATERIAL=6763643a5c45d577f4b3e1352ad20e4e5e150546
ESTADO_DIRETO=/var/lib/adm-srv-formador-direto

erro_direto() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

ajuda_direto() {
    cat <<'TXT'
Executar dentro da VM Ubuntu, como ubuntu:
  sudo bash preparar-vm-direto.sh

Pede o IP/nome do Proxmox e abre uma ligação SSH como root para obter apenas
o IP do Zabbix e o certificado público da CA da sala. Usa a autenticação SSH
normal; não guarda a palavra-passe nem copia a chave privada da CA.

Opções:
  --proxmox IP_OU_NOME   evitar a pergunta do endereço do Proxmox
  --ip-zabbix IP        configuração manual, em conjunto com --ca-cert
  --ca-cert FICHEIRO    certificado público já disponível nesta VM
  --disco-serial SERIAL disco de backup; aceita também /srv/backup já montado
  --posto ID           formador por omissão; mesmos caminhos dos formandos

Separa o material público dos parâmetros reais, que ficam só nesta VM.
Conserva volumes e dados da stack anterior e prepara Nginx, Restic, Agent 2,
CP4 e ~/parametros-posto.sh. Reutiliza Docker/Compose quando já funcionam.
O disco de backup tem de estar montado em /srv/backup ou identificado pelo
serial lab-backup-NUMERO. Só um disco vazio identificado é inicializado.
TXT
}

validar_proxmox() {
    python3 - "$1" <<'PY_HOST'
import ipaddress, re, sys
host = sys.argv[1]
try:
    ipaddress.IPv4Address(host)
except ValueError:
    if (not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?', host)
            or re.fullmatch(r'[0-9.]+', host)
            or any(not label or len(label) > 63 or label.startswith('-') or label.endswith('-') for label in host.split('.'))):
        raise SystemExit('Endereço do Proxmox inválido. Usar o IP ou nome, sem root@, porta ou URL.')
PY_HOST
}

receber_sala() {
    local servidor=$1 destino=$2
    validar_proxmox "$servidor"
    printf 'Ligação SSH ao Proxmox: root@%s\n' "$servidor"
    ssh -o ConnectTimeout=15 "root@$servidor" python3 - > "$destino" <<'PY_SALA_REMOTA'
import ipaddress, json, shlex
from pathlib import Path

def exportar(conf, certificate):
    address = None
    for line in conf.read_text().splitlines():
        words = shlex.split(line, comments=True)
        if words and words[0].startswith('IP_ZABBIX='):
            address = words[0].split('=', 1)[1]
            break
    ipaddress.IPv4Address(address)
    public = certificate.read_text()
    if 'PRIVATE KEY' in public or '-----BEGIN CERTIFICATE-----' not in public:
        raise ValueError('Fornecer apenas o certificado público da CA da sala.')
    return {'ip_zabbix': address, 'ca_publica': public}

if __name__ == '__main__':
    try:
        print(json.dumps(exportar(Path('/root/laboratorio/lab.conf'), Path('/root/laboratorio/segredos/ca-lab.crt'))))
    except (OSError, ValueError) as exc:
        raise SystemExit('Não foi possível obter a configuração da sala: ' + str(exc))
PY_SALA_REMOTA
}

ler_sala_recebida() {
    python3 - "$1" "$2" <<'PY_SALA_LOCAL'
import ipaddress, json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
address = str(ipaddress.IPv4Address(data['ip_zabbix']))
public = data['ca_publica']
if not isinstance(public, str) or 'PRIVATE KEY' in public or '-----BEGIN CERTIFICATE-----' not in public:
    raise SystemExit('A resposta não contém apenas um certificado público.')
Path(sys.argv[2]).write_text(public)
print(address)
PY_SALA_LOCAL
}

escolher_disco_direto() {
    local serial=${1:-}
    local -a encontrados=()
    if [[ -z "$serial" ]] && mountpoint -q /srv/backup; then
        return 0
    fi
    if [[ -z "$serial" ]]; then
        mapfile -t encontrados < <(lsblk -dnro SERIAL | awk '/^lab-backup-[0-9]+$/ {print}' | sort -u)
        [[ ${#encontrados[@]} -eq 1 ]] || erro_direto 'Não foi identificado um único disco lab-backup-NUMERO. Confirmar o disco de backup ou indicar --disco-serial.'
        serial=${encontrados[0]}
    fi
    [[ "$serial" =~ ^[A-Za-z0-9_-]+$ ]] || erro_direto 'Serial do disco inválido.'
    lsblk -dnro SERIAL | awk -v serial="$serial" '$1==serial {count++} END {exit count!=1}' \
        || erro_direto 'O serial não corresponde a um único disco nesta VM.'
    printf '%s\n' "$serial"
}

preparar_motor_direto() {
    export DEBIAN_FRONTEND=noninteractive
    if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
        systemctl enable --now docker
        docker info >/dev/null
        printf 'Docker e Compose existentes reutilizados.\n'
        return 0
    fi
    local pacote
    for pacote in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
        [[ $(dpkg-query -W -f='${db:Status-Status}' "$pacote" 2>/dev/null || true) != installed ]] \
            || erro_direto 'Existe uma instalação Docker incompleta. Corrigir Docker/Compose antes de continuar; os pacotes e dados foram conservados.'
    done
    source /etc/os-release
    install -d -m 0755 /etc/apt/keyrings
    curl --fail --silent --show-error --location --retry 3 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
    cat > /etc/apt/sources.list.d/docker.sources <<EOF_DOCKER_DIRETO
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER_DIRETO
    apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
    apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    docker compose version
    docker info >/dev/null
}

obter_material_direto() {
    local repo=/home/ubuntu/adm-srv url=https://github.com/Skullclamp/adm-srv.git
    if ! command -v git >/dev/null; then
        apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
        apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y git
    fi
    if [[ ! -e "$repo" ]]; then runuser -u ubuntu -- git clone "$url" "$repo"; fi
    [[ -d "$repo/.git" && ! -L "$repo" ]] || erro_direto 'A pasta ~/adm-srv existe sem um repositório válido; foi conservada.'
    [[ $(runuser -u ubuntu -- git -C "$repo" remote get-url origin) == "$url" ]] || erro_direto 'O repositório existente tem outra origem; foi conservado.'
    [[ -z $(runuser -u ubuntu -- git -C "$repo" status --porcelain) ]] || erro_direto 'Há alterações locais em ~/adm-srv. Foram conservadas; rever antes de repetir.'
    runuser -u ubuntu -- git -C "$repo" fetch --depth 1 origin "$VERSAO_MATERIAL"
    runuser -u ubuntu -- git -C "$repo" checkout --detach "$VERSAO_MATERIAL"
}

aplicar_direto() {
    local pasta=$1 posto=$2 servidor=$3 serial=$4 ca=$5 destino fase=preparacao
    local -a args_disco=()
    for destino in /root/ca-lab.crt /etc/adm-srv-formador-ref /etc/adm-srv-formador-opcoes.json; do
        [[ ! -L "$destino" ]] || erro_direto "Destino inesperado: $destino"
        if [[ -e "$destino" ]]; then cp -a -- "$destino" "$pasta/$(basename -- "$destino").antes"; fi
    done
    if [[ -f /root/ca-lab.crt ]]; then
        cmp -s "$ca" /root/ca-lab.crt || erro_direto 'Já existe outro certificado da CA em /root/ca-lab.crt. Foi conservado; confirmar a CA da sala.'
    fi
    if systemctl cat adm-srv-formador.service >/dev/null 2>&1; then
        systemctl stop adm-srv-formador.service
    fi
    install -d -m 0700 /var/lib/adm-srv-formador
    # Registo partilhado com o diagnóstico existente, também quando não há QGA.
    exec > >(tee -a /var/log/adm-srv-formador.log) 2>&1
    trap 'printf "erro-direto-%s-linha-%s\n" "$fase" "$LINENO" > /var/lib/adm-srv-formador/estado' ERR
    if [[ -f /var/lib/adm-srv-formador/pronto ]]; then
        cp -a /var/lib/adm-srv-formador/pronto /var/lib/adm-srv-formador/pronto-anterior
        rm -- /var/lib/adm-srv-formador/pronto
    fi
    [[ "$ca" -ef /root/ca-lab.crt ]] || install -m 0644 "$ca" /root/ca-lab.crt
    printf '%s\n' "$VERSAO_MATERIAL" > /etc/adm-srv-formador-ref
    chmod 0600 /etc/adm-srv-formador-ref
    python3 - "$posto" "$servidor" "$serial" <<'PY_OPCOES_DIRETO'
import json, os, sys
from pathlib import Path
path = Path('/etc/adm-srv-formador-opcoes.json')
path.write_text(json.dumps(dict(zip(('posto', 'ip_zabbix', 'disco_serial'), sys.argv[1:]))) + '\n')
path.chmod(0o600)
PY_OPCOES_DIRETO
    fase=docker
    printf 'a-preparar-docker-direto\n' > /var/lib/adm-srv-formador/estado
    preparar_motor_direto
    fase=material
    printf 'a-obter-material-direto\n' > /var/lib/adm-srv-formador/estado
    obter_material_direto
    [[ -z "$serial" ]] || args_disco=(--disco-serial "$serial" --inicializar-disco)
    fase=posto
    printf 'a-preparar-posto-direto\n' > /var/lib/adm-srv-formador/estado
    /bin/bash /home/ubuntu/adm-srv/preparar-posto.sh instalar --posto "$posto" \
        --ip-zabbix "$servidor" --ca-cert /root/ca-lab.crt --migrar-docker "${args_disco[@]}"
    test -s /home/ubuntu/parametros-posto.sh
    printf 'pronto\n' > /var/lib/adm-srv-formador/estado
    printf '%s\n' "$VERSAO_MATERIAL" > /var/lib/adm-srv-formador/pronto
    printf '\nPreparação concluída. Na shell ubuntu, executar:\nsource "$HOME/parametros-posto.sh" && validar_parametros\n'
}

executar_direto() {
    local proxmox= servidor= ca= serial= posto=formador pasta recebido
    while (($#)); do
        [[ $# -ge 2 && -n "$2" ]] || erro_direto "Falta o valor de $1"
        case "$1" in
            --proxmox) proxmox=$2 ;; --ip-zabbix) servidor=$2 ;; --ca-cert) ca=$2 ;;
            --disco-serial) serial=$2 ;; --posto) posto=$2 ;;
            *) erro_direto "Opção desconhecida: $1" ;;
        esac
        shift 2
    done
    [[ "$posto" =~ ^[A-Za-z0-9_-]+$ ]] || erro_direto 'Posto inválido.'
    [[ ! -L "$ESTADO_DIRETO" ]] || erro_direto 'Pasta de preparação inesperada.'
    install -d -m 0700 "$ESTADO_DIRETO"
    pasta=$(mktemp -d "$ESTADO_DIRETO/transferencia.XXXXXX")
    if [[ -z "$servidor" || -z "$ca" ]]; then
        if [[ -z "$proxmox" ]]; then
            read -r -p 'IP ou nome do Proxmox (o endereço usado no PuTTY): ' proxmox
        fi
        receber_sala "$proxmox" "$pasta/sala.json"
        recebido=$(ler_sala_recebida "$pasta/sala.json" "$pasta/ca-lab.crt")
        [[ -n "$servidor" ]] || servidor=$recebido
        [[ -n "$ca" ]] || ca="$pasta/ca-lab.crt"
    fi
    python3 -c 'import ipaddress,sys;ipaddress.IPv4Address(sys.argv[1])' "$servidor"
    [[ -f "$ca" && ! -L "$ca" ]] || erro_direto 'Falta o certificado público da CA nesta VM.'
    ! grep -q 'PRIVATE KEY' "$ca" || erro_direto 'Fornecer apenas a CA pública.'
    openssl x509 -in "$ca" -noout >/dev/null
    serial=$(escolher_disco_direto "$serial")
    printf '\nPosto: %s\nZabbix: %s\nDisco de backup: %s\nRegisto: /var/log/adm-srv-formador.log\n' "$posto" "$servidor" "${serial:-/srv/backup já montado}"
    aplicar_direto "$pasta" "$posto" "$servidor" "$serial" "$ca"
}

verificar_vm_direto() {
    [[ $EUID -eq 0 && ! -d /etc/pve ]] || erro_direto 'Executar com sudo dentro da VM Ubuntu, onde aparece ubuntu@formador-docker.'
    source /etc/os-release
    [[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 && $(uname -m) == x86_64 ]] || erro_direto 'Este script usa Ubuntu 26.04 amd64.'
    local ferramenta
    for ferramenta in curl python3 openssl ssh lsblk flock; do
        command -v "$ferramenta" >/dev/null || erro_direto "Falta a ferramenta $ferramenta nesta VM."
    done
}

main_direto() {
    case "${1:-}" in -h|--help|ajuda) ajuda_direto; return 0 ;; esac
    verificar_vm_direto
    local codigo=0
    umask 077
    [[ ! -L /run/lock/adm-srv-formador-direto.lock ]] || erro_direto 'Ficheiro de bloqueio inesperado.'
    flock --nonblock --conflict-exit-code 200 --close /run/lock/adm-srv-formador-direto.lock \
        /bin/bash -c 'source "$1"; shift; executar_direto "$@"' adm-srv-preparacao-direta "${BASH_SOURCE[0]}" "$@" || codigo=$?
    [[ $codigo -ne 200 ]] || erro_direto 'Outra preparação direta ainda está em execução.'
    return "$codigo"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main_direto "$@"; fi
