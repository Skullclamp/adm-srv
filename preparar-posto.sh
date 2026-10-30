#!/usr/bin/env bash
# Preparação comum: VM do formador e VMs dos formandos. Não resolve T3–T17.
set -Eeuo pipefail
umask 077
BASE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
POSTO=p1
ALUNO=ubuntu
IP_ZABBIX=
REDE_LAB=
CA_ORIGEM=
DISCO_SERIAL=
FORMATAR=nao
MIGRAR=nao
COMANDO=${1:-ajuda}
[[ $# -eq 0 ]] || shift
erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
msg() { printf '\n==> %s\n' "$*"; }

case "$COMANDO" in
    ajuda|help|-h|--help)
        cat <<'AJUDA'
sudo bash preparar-posto.sh instalar --posto p1 --ip-zabbix IP --ca-cert CAMINHO
sudo bash preparar-posto.sh verificar [--aluno ubuntu]

Usar nas VMs Ubuntu, incluindo a VM do formador. Docker e Compose já instalados.
  --posto ID          identificador atribuído na ficha; formador também é um posto
  --aluno CONTA       ubuntu por omissão; determina a pasta ~/cp4
  --ip-zabbix IP      servidor da sala, sem criar outro Zabbix na VM
  --rede-lab CIDR     por omissão: rede da interface usada para chegar ao Zabbix
  --ca-cert FICHEIRO  certificado público da CA existente da sala
  --disco-serial ID   disco de backup atribuído no Proxmox
  --inicializar-disco permite formatar somente um disco vazio com esse serial
  --migrar-docker     adapta a antiga stack adm-srv-formador, conservando os dados

Sem disco indicado, /srv/backup tem de estar montado previamente.
AJUDA
        exit 0 ;;
    instalar|verificar) ;;
    *) erro 'Comando inválido; consultar ajuda.' ;;
esac

while (($#)); do
    case "$1" in
        --migrar-docker) MIGRAR=sim; shift; continue ;;
        --inicializar-disco) FORMATAR=sim; shift; continue ;;
    esac
    [[ $# -ge 2 && -n "$2" ]] || erro "Falta valor para $1"
    case "$1" in
        --posto) POSTO=$2 ;; --aluno) ALUNO=$2 ;; --ip-zabbix) IP_ZABBIX=$2 ;;
        --rede-lab) REDE_LAB=$2 ;; --ca-cert) CA_ORIGEM=$2 ;; --disco-serial) DISCO_SERIAL=$2 ;;
        *) erro "Opção desconhecida: $1" ;;
    esac
    shift 2
done

[[ $EUID -eq 0 && ! -d /etc/pve ]] || erro 'Executar com sudo dentro da VM Ubuntu.'
[[ "$POSTO" =~ ^[a-zA-Z0-9_-]+$ && "$ALUNO" =~ ^[a-z_][a-z0-9_-]*$ ]] || erro 'Posto ou conta inválidos.'
CASA=$(getent passwd "$ALUNO" | cut -d: -f6)
[[ -n "$CASA" && "$CASA" == /home/* && -d "$CASA" && ! -L "$CASA" ]] || erro 'Conta sem uma pasta válida em /home.'
GRUPO=$(id -gn "$ALUNO")
PARAMETROS="$CASA/parametros-posto.sh"
CP4="$CASA/cp4"
LEGADO="$CASA/adm-srv/formador/docker-lab"
STATE=/var/lib/adm-srv-posto
install -d -m 0700 "$STATE"
exec 8>"$STATE/preparacao.lock"
flock -n 8 || erro 'Já há uma preparação em execução.'
trap 'rc=$?; printf "Preparação interrompida na linha %s (código %s); os dados foram conservados.\n" "$LINENO" "$rc" >&2' ERR

verificar() {
    [[ -r "$PARAMETROS" ]] || erro 'Falta parametros-posto.sh; executar instalar.'
    source "$PARAMETROS"
    validar_parametros
    docker compose -f "$COMPOSE_CP4" config --quiet
    docker compose -f "$COMPOSE_CP4" ps app
    curl --retry 10 --retry-connrefused --retry-delay 1 --max-time 10 --fail --silent --show-error http://127.0.0.1:8000/dados.txt
    [[ -s "$AMOSTRA_ORIGEM/ficheiro-1.txt" && -s "$CA_CERT" ]] || erro 'Falta a amostra T1 ou a CA pública.'
    mountpoint -q "$PONTO_REPO" || erro '/srv/backup não está montado.'
    systemctl is-active --quiet nginx
    systemctl is-active --quiet zabbix-agent2
    restic version
    test -s /opt/lab/modelos/backup-sessao.service
    test -s /opt/lab/modelos/backup-sessao.timer
    printf '\nPreparação comum verificada. Continuar T0–T17 pelo mesmo guia.\n'
}
if [[ "$COMANDO" == verificar ]]; then verificar; exit 0; fi

source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]] || erro 'Este material usa Ubuntu 26.04 LTS.'
command -v docker >/dev/null && docker compose version >/dev/null || erro 'Instalar Docker e o plugin Compose antes de preparar o posto.'
[[ -f "$BASE/cp4/compose.yaml" && -f "$BASE/formador/parametros.exemplo.sh" ]] || erro 'Executar a partir de uma cópia completa do repositório adm-srv.'
[[ -f "$CA_ORIGEM" ]] || erro 'Indicar --ca-cert com o certificado público da CA existente.'
openssl x509 -in "$CA_ORIGEM" -noout >/dev/null
grep -q 'PRIVATE KEY' "$CA_ORIGEM" && erro 'Fornecer só o certificado público, sem chave privada.'
python3 - "$IP_ZABBIX" "$REDE_LAB" <<'PY_REDE'
import ipaddress, sys
ipaddress.IPv4Address(sys.argv[1])
if sys.argv[2]:
    ipaddress.IPv4Network(sys.argv[2], strict=False)
PY_REDE
IP_VM=$(ip -4 route get "$IP_ZABBIX" | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1);exit}}')
INTERFACE=$(ip -4 route get "$IP_ZABBIX" | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1);exit}}')
[[ -n "$IP_VM" && -n "$INTERFACE" ]] || erro 'Não foi encontrada uma rota IPv4 para o Zabbix.'
if [[ -z "$REDE_LAB" ]]; then
    ENDERECO=$(ip -4 -o addr show dev "$INTERFACE" | awk -v ip="$IP_VM" 'index($4,ip"/")==1 {print $4;exit}')
    REDE_LAB=$(python3 -c 'import ipaddress,sys;print(ipaddress.ip_interface(sys.argv[1]).network)' "$ENDERECO")
fi

msg 'Pacotes do posto: Nginx, Restic, UFW e Agent 2 no Ubuntu'
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y nginx restic ufw curl ca-certificates openssl util-linux
if ! dpkg-query -W -f='${Version}' zabbix-agent2 2>/dev/null | grep -q '^1:7\.0\|^7\.0'; then
    DEB="zabbix-release_latest_7.0+ubuntu${VERSION_ID}_all.deb"
    curl --fail --silent --show-error --location --retry 3 \
        "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/$DEB" -o "$STATE/zabbix-release.deb"
    dpkg -i "$STATE/zabbix-release.deb"
    apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 update
    apt-get -o Acquire::Retries=3 -o DPkg::Lock::Timeout=120 install -y zabbix-agent2
fi
dpkg-query -W -f='${Version}' zabbix-agent2 | grep -q '^1:7\.0\|^7\.0' \
    || erro 'A versão instalada do Agent 2 não é 7.0. Rever sem substituir automaticamente uma instalação diferente.'

msg 'Disco de backup, no mesmo ponto /srv/backup dos formandos'
install -d -m 0700 /srv/backup
if ! mountpoint -q /srv/backup; then
    [[ "$DISCO_SERIAL" =~ ^[a-zA-Z0-9_-]+$ ]] || erro 'Montar o disco de backup ou indicar --disco-serial.'
    DISCO=$(lsblk -dnpo NAME,SERIAL | awk -v serial="$DISCO_SERIAL" '$2==serial {print $1}')
    [[ "$DISCO" == /dev/* && "$DISCO" != *$'\n'* && -b "$DISCO" ]] || erro 'O serial não identificou um único disco de backup.'
    [[ $(lsblk -nrpo NAME "$DISCO" | wc -l) -eq 1 ]] || erro 'O disco tem partições: requer revisão manual.'
    [[ -z $(lsblk -nrpo MOUNTPOINTS "$DISCO" | tr -d '[:space:]') ]] || erro 'O disco já está em utilização; não será alterado.'
    TIPO=$(blkid -s TYPE -o value "$DISCO" || true)
    if [[ -z "$TIPO" ]]; then
        [[ "$FORMATAR" == sim && -z $(wipefs --no-act --noheadings --output TYPE "$DISCO") ]] || erro 'Disco sem filesystem: só inicializar se estiver vazio e com --inicializar-disco.'
        mkfs.ext4 -q -L lab-backup "$DISCO"
    else
        [[ "$TIPO" == ext4 ]] || erro 'O disco existente não é ext4; rever sem formatar.'
    fi
    UUID=$(blkid -s UUID -o value "$DISCO")
    [[ -n "$UUID" ]] || erro 'Não foi possível ler o UUID do disco.'
    if awk '$1 !~ /^#/ && $2=="/srv/backup" {found=1} END {exit !found}' /etc/fstab; then
        awk -v uuid="UUID=$UUID" '$1==uuid && $2=="/srv/backup" {ok=1} END {exit !ok}' /etc/fstab || erro 'Já existe outra entrada fstab para /srv/backup.'
    else
        cp -a /etc/fstab "$STATE/fstab.antes-$(date -u +%Y%m%dT%H%M%S)"
        printf 'UUID=%s /srv/backup ext4 defaults,nofail 0 2\n' "$UUID" >> /etc/fstab
    fi
    systemctl daemon-reload
    mount /srv/backup
fi

if [[ "$MIGRAR" == sim ]]; then
    msg 'Guardar a antiga configuração e conservar os volumes Docker'
    if [[ -d "$LEGADO/.runtime" ]]; then
        MIGRACAO="$STATE/migracao-$(date -u +%Y%m%dT%H%M%S)"
        install -d -m 0700 "$MIGRACAO"
        cp -a "$LEGADO/.runtime" "$MIGRACAO/runtime"
        cp -a "$LEGADO/compose.yaml" "$MIGRACAO/compose-legado.yaml"
    fi
    IDS=$(docker ps -aq --filter label=com.docker.compose.project=adm-srv-formador)
    if [[ -n "$IDS" ]]; then
        mapfile -t CONTENTORES <<< "$IDS"
        docker stop "${CONTENTORES[@]}"
    fi
    if docker volume inspect adm-srv-formador_cp4_dados >/dev/null 2>&1; then
        docker volume create --label com.docker.compose.project=cp4 \
            --label com.docker.compose.volume=dados cp4_dados >/dev/null
        # Só copiar para um destino vazio ou já idêntico. Os dois volumes ficam guardados.
        docker run --rm \
            --mount type=volume,src=adm-srv-formador_cp4_dados,dst=/origem,readonly \
            --mount type=volume,src=cp4_dados,dst=/destino \
            python:3.13-slim python -c '
from pathlib import Path
import hashlib, shutil
def manifest(root):
    result={}
    for path in root.rglob("*"):
        if path.is_symlink():
            raise SystemExit("A origem contém uma ligação simbólica; rever a migração.")
        if path.is_file():
            result[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
    return result
source, target=Path("/origem"), Path("/destino")
before=manifest(source)
if any(target.iterdir()):
    if manifest(target)!=before:
        raise SystemExit("Os volumes antigo e cp4_dados contêm dados diferentes. Ambos foram conservados; decidir a origem antes de retomar.")
else:
    shutil.copytree(source, target, dirs_exist_ok=True)
if manifest(target)!=before:
    raise SystemExit("A verificação da cópia falhou; a origem foi conservada.")'
    fi
fi

msg 'CP4 comum: ~/cp4, projeto cp4, serviço app, volume cp4_dados'
install -d -m 0755 -o "$ALUNO" -g "$GRUPO" "$CP4"
[[ ! -L "$CP4" && ! -L "$CP4/compose.yaml" ]] || erro 'A pasta ou o Compose não podem ser ligações simbólicas.'
if [[ -f "$CP4/compose.yaml" ]]; then
    docker compose -f "$CP4/compose.yaml" config --format json | python3 -c '
import json,sys
c=json.load(sys.stdin)
app=c.get("services",{}).get("app",{})
ports=any(str(p.get("published"))=="8000" and p.get("target")==8000 and p.get("host_ip")=="127.0.0.1" for p in app.get("ports",[]))
if c.get("name")!="cp4" or c.get("volumes",{}).get("dados",{}).get("name")!="cp4_dados" or not ports or not any(v.get("source")=="dados" and v.get("target")=="/dados" for v in app.get("volumes",[])):
    raise SystemExit("O Compose existente não corresponde ao modelo comum. Foi conservado; rever antes de prosseguir.")'
else
    install -m 0644 -o "$ALUNO" -g "$GRUPO" "$BASE/cp4/compose.yaml" "$CP4/compose.yaml"
fi
docker compose -f "$CP4/compose.yaml" up -d app
docker compose -f "$CP4/compose.yaml" exec -T app sh -c '
    test -e /dados/index.html || printf "%s\n" "<h1>CP4 - aplicacao do laboratorio</h1>" > /dados/index.html
    test -e /dados/dados.txt || printf "%s\n" "CP4-DADOS-OK" > /dados/dados.txt'
VOLUME_CP4_PATH=$(docker volume inspect cp4_dados --format '{{.Mountpoint}}')

msg 'Amostra T1, CA pública e agente nos caminhos comuns'
install -d -m 0755 /srv/amostra-t1 /etc/ssl/lab /etc/nginx/tls /opt/lab/modelos
for n in 1 2 3 4 5; do
    if [[ ! -e "/srv/amostra-t1/ficheiro-$n.txt" ]]; then
        printf 'amostra %s\n' "$n" > "/srv/amostra-t1/ficheiro-$n.txt"
        chmod 0644 "/srv/amostra-t1/ficheiro-$n.txt"
    fi
done
for ficheiro in hostname os-release; do [[ -e "/srv/amostra-t1/$ficheiro" ]] || cp -a "/etc/$ficheiro" /srv/amostra-t1/; done
if [[ -f /etc/ssl/lab/ca-lab.crt ]]; then
    cmp -s "$CA_ORIGEM" /etc/ssl/lab/ca-lab.crt || erro 'Já existe uma CA diferente; foi conservada. Confirmar a CA correta da sala.'
else
    install -m 0644 "$CA_ORIGEM" /etc/ssl/lab/ca-lab.crt
fi
PSK=/etc/zabbix/zabbix_agent2.psk
if [[ ! -s "$PSK" ]]; then openssl rand -hex 32 > "$PSK"; fi
chown root:zabbix "$PSK"; chmod 0640 "$PSK"
cp -a /etc/zabbix/zabbix_agent2.conf "$STATE/zabbix_agent2.conf.antes-$(date -u +%Y%m%dT%H%M%S)"
python3 - "$IP_ZABBIX" "$POSTO" <<'PY_AGENT'
from pathlib import Path
import re, sys
path=Path('/etc/zabbix/zabbix_agent2.conf')
text=path.read_text()
values={'Server':sys.argv[1], 'Hostname':'srv-'+sys.argv[2], 'TLSAccept':'psk',
        'TLSPSKIdentity':'PSK-'+sys.argv[2], 'TLSPSKFile':'/etc/zabbix/zabbix_agent2.psk'}
for key,value in values.items():
    text=re.sub(r'^'+key+r'=.*\n?', '', text, flags=re.M)
    text+=f'\n{key}={value}\n'
text=re.sub(r'^ServerActive=.*$', '# ServerActive desativado: recolha passiva', text, flags=re.M)
path.write_text(text)
PY_AGENT
systemctl enable --now nginx zabbix-agent2
systemctl restart zabbix-agent2
# UFW mantém o estado atual; T4 trata da política de exposição e da ativação.

msg 'Ficha de parâmetros e modelos T10 comuns'
python3 - "$BASE/formador/parametros.exemplo.sh" "$PARAMETROS" "$POSTO" "$IP_VM" "$REDE_LAB" "$IP_ZABBIX" "$CP4" "$VOLUME_CP4_PATH" <<'PY_PARAMS'
from pathlib import Path
import re, shlex, shutil, sys, time
template, destination, posto, ip, network, zabbix, cp4, data=sys.argv[1:]
values={
'POSTO':posto,'IP_VM':ip,'REDE_LAB':network,'IP_ZABBIX':zabbix,'NOME_SITE':posto+'.lab.test',
'COMPOSE_CP4':cp4+'/compose.yaml','VOLUME_CP4':'cp4_dados','VOLUME_CP4_PATH':data,
'AMOSTRA_ORIGEM':'/srv/amostra-t1','WEB_ROOT':'/var/www/'+posto,
'NGINX_INCLUDE':'/etc/nginx/conf.d/'+posto+'.conf','ACCESS_LOG':'/var/log/nginx/'+posto+'.access.log',
'ERROR_LOG':'/var/log/nginx/'+posto+'.error.log','CA_CERT':'/etc/ssl/lab/ca-lab.crt','DIR_TLS':'/etc/nginx/tls',
'PONTO_REPO':'/srv/backup','REPO':'/srv/backup/'+posto,'PWFILE':'/root/.restic-'+posto+'.pw',
'URL_ZABBIX':'http://'+zabbix+'/zabbix','NOME_LOGICO_DO_POSTO':'srv-'+posto,
'GRUPO_HOSTS':'Postos/'+posto,'IDENTIFICADOR_PUBLICO':'PSK-'+posto,
'PSK_FILE':'/etc/zabbix/zabbix_agent2.psk',
}
text=Path(template).read_text()
for key,value in values.items():
    text=re.sub(r'^'+key+r'=.*$',key+'='+shlex.quote(value),text,flags=re.M)
path=Path(destination)
if path.is_symlink():
    raise SystemExit('A ficha não pode ser uma ligação simbólica.')
if path.exists() and path.read_text()!=text:
    shutil.copy2(path, str(path)+'.antes-'+str(time.time_ns()))
path.write_text(text)
PY_PARAMS
chown "$ALUNO:$GRUPO" "$PARAMETROS"; chmod 0600 "$PARAMETROS"
source "$PARAMETROS"
if [[ ! -f "$PWFILE" ]]; then
    [[ ! -f "$REPO/config" ]] || erro 'Já existe um repositório sem o segredo correspondente. Recuperar a custódia.'
    openssl rand -base64 32 > "$PWFILE"; chmod 0600 "$PWFILE"
fi
cat > /opt/lab/modelos/backup-sessao.service <<EOF_SERVICE
[Unit]
Description=Backup Restic - sessao final
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/restic --repo $REPO --password-file $PWFILE backup $WEB_ROOT /etc/nginx $VOLUME_CP4_PATH --tag sessao-final --tag timer
EOF_SERVICE
cat > /opt/lab/modelos/backup-sessao.timer <<'EOF_TIMER'
[Unit]
Description=Agendamento do backup Restic - sessao final

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF_TIMER
chmod 0644 /opt/lab/modelos/backup-sessao.*
verificar
