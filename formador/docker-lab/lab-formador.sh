#!/usr/bin/env bash
# Laboratório completo do formador. Executar numa VM Ubuntu com Docker Compose v2.
set -Eeuo pipefail
BASE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
RUNTIME="$BASE/.runtime"
ENV_FILE="$RUNTIME/lab.env"
PROJETO=adm-srv-formador

erro() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }
mensagem() { printf '\n==> %s\n' "$*"; }
trap 'printf "Falha na linha %s. O trabalho e os volumes foram conservados.\n" "$LINENO" >&2' ERR

ajuda() {
    cat <<'TXT'
Uso: bash lab-formador.sh <comando>

  subir                         prepara e inicia toda a stack, Zabbix e primeiro backup
  preparar                      gera parâmetros, certificados e dados iniciais
  estado                        lista os serviços
  verificar                     confirma HTTPS, CP4, recolha Zabbix e repositório
  acessos                       mostra URLs e credenciais locais do Zabbix
  backup                        cria um snapshot Restic
  snapshots                     lista snapshots
  retencao                      simula retenção; não remove snapshots
  restaurar [ID] [ficheiro]      repõe estado.html ou teste-restauro.html; ID por omissão: latest
  falha <id>                    t6-1, t6-404, t6-502, t14, t16-a, t16-b ou t16-c
  repor <id>                    reverte a falha ativa, conservando os restantes dados
  logs [servico]                últimas linhas dos logs dos contentores
  carga [segundos]              carga limitada de CPU; 30 segundos por omissão, máximo 120
  ca                            imprime apenas o certificado público da CA
  versoes                       mostra versões das ferramentas e imagens usadas
  parar                         para a stack, mantendo dados, segredos e backups

Os serviços web ficam em loopback: HTTP 8080, HTTPS 8443 e Zabbix 8081.
Não são alteradas as VMs nem os serviços nativos dos exercícios dos formandos.
TXT
}

dependencias() {
    command -v docker >/dev/null || erro 'Instalar Docker antes de executar este script.'
    command -v openssl >/dev/null || erro 'Instalar o pacote openssl.'
    command -v flock >/dev/null || erro 'Instalar util-linux (flock).'
    docker compose version >/dev/null || erro 'É necessário Docker Compose v2.'
    docker info >/dev/null 2>&1 || erro 'Sem acesso ao Docker. Na VM, executa com sudo ou uma conta autorizada.'
}

carregar() {
    [[ -f "$ENV_FILE" && -f "$RUNTIME/.lab-formador" ]] || erro 'Executar primeiro: preparar ou subir.'
    # Ficheiro privado gerado por este script; rever antes de editar manualmente.
    set -a
    source "$ENV_FILE"
    set +a
    [[ "${PROJECT_NAME:-}" == "$PROJETO" ]] || erro 'O nome do projeto foi alterado; recusar gerir outro laboratório.'
    [[ "${BIND_IP:-}" == 127.0.0.1 ]] || erro 'Este modelo usa loopback; usar um túnel SSH para o acesso remoto.'
    local nome valor
    for nome in HTTP_PORT HTTPS_PORT ZABBIX_PORT; do
        valor=${!nome}
        [[ "$valor" =~ ^[1-9][0-9]*$ ]] && ((valor <= 65535)) || erro "Porta inválida: $nome"
    done
    [[ "$HTTP_PORT" != "$HTTPS_PORT" && "$HTTP_PORT" != "$ZABBIX_PORT" && "$HTTPS_PORT" != "$ZABBIX_PORT" ]] \
        || erro 'As três portas publicadas devem ser diferentes.'
    [[ "$BACKUP_INTERVAL" =~ ^[1-9][0-9]*$ ]] && ((BACKUP_INTERVAL >= 30 && BACKUP_INTERVAL <= 86400)) \
        || erro 'BACKUP_INTERVAL deve ficar entre 30 e 86400 segundos.'
}

dc() { docker compose --project-directory "$BASE" --env-file "$ENV_FILE" -p "$PROJETO" -f "$BASE/compose.yaml" "$@"; }
controle() { dc run --rm --no-deps ferramentas "$@"; }
restic_lab() { dc run --rm --no-deps restic "$@"; }
trancar() { exec 9>"$RUNTIME/.controlo.lock"; flock -n 9 || erro 'Há outro comando de gestão em execução.'; }

preparar() {
    umask 077
    mkdir -p "$RUNTIME"
    [[ ! -L "$RUNTIME" ]] || erro '.runtime não pode ser uma ligação simbólica.'
    chmod 0700 "$RUNTIME"
    trancar
    if [[ ! -f "$ENV_FILE" ]]; then
        [[ ! -f "$RUNTIME/.lab-formador" ]] || erro 'Falta lab.env: recuperar a cópia de custódia, sem gerar segredos novos.'
        [[ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJETO")" ]] \
            || erro 'Já existem volumes deste laboratório sem lab.env. Recuperar os parâmetros anteriores.'
        {
            printf 'PROJECT_NAME=%s\n' "$PROJETO"
            printf 'BIND_IP=127.0.0.1\nHTTP_PORT=8080\nHTTPS_PORT=8443\nZABBIX_PORT=8081\n'
            printf 'BACKUP_INTERVAL=1800\nZABBIX_TAG=ubuntu-7.0-latest\n'
            printf 'DB_PASSWORD=Db1_%s\n' "$(openssl rand -hex 20)"
            printf 'ZBX_ADMIN_PASSWORD=Aa1_%s\n' "$(openssl rand -hex 16)"
            printf 'AGENT_PSK=%s\n' "$(openssl rand -hex 32)"
        } > "$ENV_FILE"
        printf 'adm-srv-formador-v1\n' > "$RUNTIME/.lab-formador"
    fi
    chmod 0600 "$ENV_FILE"
    carregar
    mkdir -p "$RUNTIME/segredos" "$RUNTIME/ca" "$RUNTIME/tls" "$RUNTIME/nginx"
    chmod 0700 "$RUNTIME/segredos"
    chmod 0755 "$RUNTIME/ca" "$RUNTIME/tls" "$RUNTIME/nginx"
    if [[ ! -s "$RUNTIME/segredos/restic.pw" ]]; then
        [[ ! -f "$RUNTIME/.repositorio-inicializado" ]] || erro 'Falta o segredo Restic; recuperar a custódia.'
        openssl rand -base64 48 > "$RUNTIME/segredos/restic.pw"
    fi
    chmod 0600 "$RUNTIME/segredos/restic.pw"
    if [[ ! -e "$RUNTIME/ca/ca.crt" ]]; then
        [[ ! -e "$RUNTIME/segredos/ca.key" ]] || erro 'CA incompleta: recuperar certificado/chave originais.'
        openssl req -x509 -newkey rsa:3072 -nodes -days 365 \
            -keyout "$RUNTIME/segredos/ca.key" -out "$RUNTIME/ca/ca.crt" \
            -subj '/CN=CA Laboratorio Formador Docker' \
            -addext 'basicConstraints=critical,CA:TRUE' \
            -addext 'keyUsage=critical,keyCertSign,cRLSign'
    fi
    [[ -s "$RUNTIME/segredos/ca.key" ]] || erro 'Falta a chave da CA existente.'
    if [[ ! -e "$RUNTIME/tls/site.crt" ]]; then
        [[ ! -e "$RUNTIME/tls/site.key" ]] || erro 'Certificado incompleto: conservar a chave e recuperar a emissão.'
        openssl req -new -newkey rsa:3072 -nodes \
            -keyout "$RUNTIME/tls/site.key" -out "$RUNTIME/segredos/site.csr" \
            -subj '/CN=formador.lab.test' -addext 'subjectAltName=DNS:formador.lab.test,DNS:localhost,IP:127.0.0.1'
        printf '%s\n' 'basicConstraints=critical,CA:FALSE' 'keyUsage=critical,digitalSignature,keyEncipherment' \
            'extendedKeyUsage=serverAuth' 'subjectAltName=DNS:formador.lab.test,DNS:localhost,IP:127.0.0.1' \
            > "$RUNTIME/segredos/extensoes.cnf"
        openssl x509 -req -in "$RUNTIME/segredos/site.csr" \
            -CA "$RUNTIME/ca/ca.crt" -CAkey "$RUNTIME/segredos/ca.key" -CAcreateserial \
            -CAserial "$RUNTIME/segredos/ca.srl" -days 30 -sha256 \
            -extfile "$RUNTIME/segredos/extensoes.cnf" -out "$RUNTIME/tls/site.crt"
    fi
    chmod 0600 "$RUNTIME/segredos/ca.key" "$RUNTIME/tls/site.key"
    chmod 0644 "$RUNTIME/ca/ca.crt" "$RUNTIME/tls/site.crt"
    openssl verify -CAfile "$RUNTIME/ca/ca.crt" "$RUNTIME/tls/site.crt"
    openssl x509 -in "$RUNTIME/tls/site.crt" -checkend 0 -noout || erro 'O certificado expirou. Renovar a emissão com a CA existente.'
    if [[ ! -e "$RUNTIME/nginx/default.conf" ]]; then
        sed "s/__HTTPS_PORT__/$HTTPS_PORT/g" "$BASE/nginx.conf.template" > "$RUNTIME/nginx/default.conf"
    fi
    chmod 0644 "$RUNTIME/nginx/default.conf"
    dc config --quiet
    controle inicializar
    mensagem 'Preparação concluída. Os dados existentes foram conservados.'
}

inicializar_repositorio() {
    dc run --rm --no-deps --entrypoint /bin/sh restic -c \
        'if [ -f /repo/config ]; then restic --retry-lock 1m snapshots >/dev/null; else restic init; fi'
    touch "$RUNTIME/.repositorio-inicializado"
}

backup() {
    restic_lab backup /origens/site /origens/nginx /origens/cp4 /origens/tls \
        --host formador-docker --tag laboratorio --tag "${1:-manual}"
}

acessos() {
    printf '\nSite HTTP:  http://localhost:%s\nSite HTTPS: https://localhost:%s\nZabbix:     http://localhost:%s\n' \
        "$HTTP_PORT" "$HTTPS_PORT" "$ZABBIX_PORT"
    printf 'Zabbix — utilizador: Admin\nPalavra-passe: %s\n' "$ZBX_ADMIN_PASSWORD"
    printf 'CA pública: %s/ca/ca.crt\nParâmetros e segredos: %s (não publicar)\n' "$RUNTIME" "$RUNTIME"
}

comando=${1:-ajuda}
case "$comando" in ajuda|help|-h|--help) ajuda; exit 0 ;; esac
dependencias
if [[ "$comando" == preparar || "$comando" == subir ]]; then
    preparar
else
    carregar
fi

case "$comando" in
    preparar) ;;
    subir)
        mensagem 'A iniciar aplicação, site e Zabbix'
        dc up -d db zabbix-server zabbix-web agent cp4 web
        controle configurar-zabbix
        inicializar_repositorio
        if [[ ! -f "$RUNTIME/.primeiro-backup" ]]; then
            backup estado-inicial
            touch "$RUNTIME/.primeiro-backup"
        else
            backup arranque
        fi
        dc up -d agendador
        controle verificar
        restic_lab check
        printf '\nStack preparada. Consultar: bash lab-formador.sh acessos\n'
        ;;
    estado) dc ps -a ;;
    acessos) acessos ;;
    verificar) controle verificar; restic_lab check; restic_lab snapshots ;;
    backup) trancar; backup manual ;;
    snapshots) restic_lab snapshots ;;
    retencao)
        restic_lab forget --dry-run --tag laboratorio --keep-last 3 --keep-daily 7 --keep-weekly 4
        ;;
    restaurar)
        trancar
        snapshot=${2:-latest}
        ficheiro=${3:-estado.html}
        case "$ficheiro" in estado.html|teste-restauro.html) ;; *) erro 'Só se pode repor estado.html ou teste-restauro.html.' ;; esac
        stage="restauro-$(date -u +%Y%m%dT%H%M%S)-$RANDOM"
        restic_lab restore "$snapshot" --target "/restauro/$stage" --include "/origens/site/$ficheiro"
        controle promover "$stage" "$ficheiro"
        controle verificar-web
        ;;
    falha)
        trancar
        id=${2:?Indicar o identificador da falha}
        controle falha "$id"
        case "$id" in
            t6-404) dc exec -T web nginx -t; dc exec -T web nginx -s reload ;;
            t6-502) dc stop cp4 ;;
            t14) dc stop web ;;
            t16-b) dc restart web ;;
        esac
        printf 'Falha %s introduzida. Aguardar a recolha do Zabbix e consultar os logs.\n' "$id"
        ;;
    repor)
        trancar
        controle repor "${2:?Indicar a falha ativa}"
        dc up -d cp4 web
        dc restart web
        controle verificar-web
        ;;
    logs)
        servico=${2:-}
        case "$servico" in
            '') dc logs --tail 60 --timestamps ;;
            web|cp4|agent|zabbix-server|zabbix-web|db|agendador) dc logs --tail 60 --timestamps "$servico" ;;
            *) erro 'Serviço desconhecido para logs.' ;;
        esac
        ;;
    carga)
        segundos=${2:-30}
        [[ "$segundos" =~ ^[1-9][0-9]*$ ]] && ((segundos <= 120)) || erro 'Duração permitida: 1–120 segundos.'
        controle carga "$segundos"
        ;;
    ca) cat "$RUNTIME/ca/ca.crt" ;;
    versoes) docker version; docker compose version; dc images; restic_lab version ;;
    parar) trancar; dc down ;;
    *) ajuda; erro "Comando desconhecido: $comando" ;;
esac
