# Modelo didático: copiar para ~/parametros-posto.sh e preencher localmente.
# Não inclui endereços, credenciais ou caminhos privados da infraestrutura.
# Carregar apenas depois de rever: source "$HOME/parametros-posto.sh"

# Identificação, rede e nomes — obter na ficha privada do posto.
POSTO=""
IP_VM=""
REDE_LAB=""
IP_ZABBIX=""
NOME_SITE=""
PORTA_HTTP=80
PORTA_HTTPS=443
PORTA_BACKEND=8000

# CP4 — confirmar se foi criada pelo formando ou fornecida como referência.
COMPOSE_CP4=""
VOLUME_CP4="cp4_dados"
VOLUME_CP4_PATH=""  # preencher após docker volume inspect na VM do posto

# Caminhos da VM do posto — copiar da ficha de parâmetros.
AMOSTRA_ORIGEM=""
WEB_ROOT=""
NGINX_INCLUDE=""
ACCESS_LOG=""
ERROR_LOG=""
CA_CERT=""          # certificado público da CA já distribuída
DIR_TLS=""          # neste percurso, dentro da árvore /etc/nginx
PONTO_REPO=""       # ponto de montagem do disco de backup
REPO=""
PWFILE=""           # referência a um ficheiro protegido; nunca o valor do segredo
CALENDARIO="*:0/30"

# Zabbix — valores públicos de configuração, sem a PSK.
URL_ZABBIX=""
NOME_LOGICO_DO_POSTO=""
GRUPO_HOSTS=""
IDENTIFICADOR_PUBLICO=""
PSK_FILE=""             # ficheiro da PSK na VM do posto
PSK_TESTE_ZABBIX=""     # ficheiro privado para zabbix_get na VM Zabbix

# Só na cópia da máquina do formador / Proxmox.
ALUNO=""                # conta SSH do posto
CHAVE_SSH_FORMADOR=""    # caminho da chave, sem copiar o seu conteúdo
LAB_FORMADOR=""         # pasta privada que já contém formador.sh
CA_CERT_FORMADOR=""     # certificado da CA existente no formador
CA_CHAVE_FORMADOR=""    # caminho da chave da mesma CA; não criar outra CA nesta fase

validar_parametros() {
    local nome valor
    for nome in POSTO IP_VM REDE_LAB IP_ZABBIX NOME_SITE COMPOSE_CP4 AMOSTRA_ORIGEM \
        WEB_ROOT NGINX_INCLUDE ACCESS_LOG ERROR_LOG CA_CERT DIR_TLS \
        PONTO_REPO REPO PWFILE NOME_LOGICO_DO_POSTO GRUPO_HOSTS IDENTIFICADOR_PUBLICO; do
        if [[ -z "${!nome}" ]]; then
            printf 'Preencher o parâmetro %s na cópia local.\n' "$nome" >&2
            return 1
        fi
    done
    [[ "$POSTO" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "POSTO inválido." >&2; return 1; }
    [[ "$NOME_SITE" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { echo "NOME_SITE inválido." >&2; return 1; }
    for nome in COMPOSE_CP4 AMOSTRA_ORIGEM WEB_ROOT NGINX_INCLUDE ACCESS_LOG ERROR_LOG CA_CERT DIR_TLS PONTO_REPO REPO PWFILE; do
        valor=${!nome}
        if [[ "$valor" != /* || "$valor" == / || "$valor" == *[[:space:]]* ]]; then
            printf '%s deve ser um caminho absoluto dedicado, sem espaços e diferente de /.\n' "$nome" >&2
            return 1
        fi
    done
    for nome in PORTA_HTTP PORTA_HTTPS PORTA_BACKEND; do
        valor=${!nome}
        if [[ ! "$valor" =~ ^[1-9][0-9]*$ ]] || (( valor > 65535 )); then
            printf 'Porta inválida em %s.\n' "$nome" >&2
            return 1
        fi
    done
    case "$DIR_TLS" in
        /etc/nginx/*) ;;
        *) echo "Neste guia, DIR_TLS deve ficar dentro de /etc/nginx para integrar o backup." >&2; return 1 ;;
    esac
    case "$REPO" in
        "$PONTO_REPO"/*) ;;
        *) echo "REPO deve ser uma pasta dedicada dentro de PONTO_REPO." >&2; return 1 ;;
    esac
    printf 'Parâmetros básicos preenchidos. Confirmar os alvos na VM antes de alterar ficheiros.\n'
}

restic_lab() {
    [[ -n "$REPO" && -n "$PWFILE" ]] || { echo "Preencher REPO e PWFILE." >&2; return 1; }
    sudo restic --repo "$REPO" --password-file "$PWFILE" "$@"
}

teste_http() {
    curl --silent --show-error --max-time 10 \
        --resolve "${NOME_SITE}:${PORTA_HTTP}:${IP_VM}" \
        "http://${NOME_SITE}:${PORTA_HTTP}${1:-/estado.html}"
}

teste_https() {
    curl --fail --silent --show-error --max-time 10 --cacert "$CA_CERT" \
        --resolve "${NOME_SITE}:${PORTA_HTTPS}:${IP_VM}" \
        "https://${NOME_SITE}:${PORTA_HTTPS}${1:-/estado.html}"
}

codigo_https() {
    curl --silent --show-error --max-time 10 --cacert "$CA_CERT" \
        --resolve "${NOME_SITE}:${PORTA_HTTPS}:${IP_VM}" \
        --output /dev/null --write-out '%{http_code}\n' \
        "https://${NOME_SITE}:${PORTA_HTTPS}${1:-/estado.html}"
}
