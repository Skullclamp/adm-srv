# Guia de resolução passo a passo — Sessão final M4–M8

**Material do formador · Preparação CP4 e tarefas T0–T17 · Versão 1.0 — 30-10-2026**

Este guia acompanha o [enunciado](../README.md), a [preparação CP4](../PREPARAR_CP4.md) e a [folha de respostas](../FOLHA_DE_RESPOSTAS.md). Contém soluções e cenários de falha. Como o repositório é público, os formandos também o podem consultar.

## Preparar a execução

1. Atribui um posto a cada formando. Confirma ferramentas instaladas, acesso SSH, consola de recuperação, disco de backup, CA distribuída e Zabbix operacional.
2. Usa uma cópia local de [parametros.exemplo.sh](parametros.exemplo.sh), preenchida com a ficha do posto. Os valores reais ficam fora deste repositório.
3. Nas novas shells, carrega a cópia revista. Na **VM do posto**, valida os parâmetros:

```bash
source "$HOME/parametros-posto.sh"
validar_parametros
```

4. Não avances se a validação falhar. Os caminhos têm de corresponder ao posto e os segredos têm de estar disponíveis pelos meios preparados.
5. Executa cada bloco no contexto indicado. A shell deve conservar as variáveis; se abrires outra sessão, volta a carregar os parâmetros. Não atives um `set -e` global numa sessão usada para introduzir falhas: algumas operações vão falhar de propósito.

As funções `teste_http`, `teste_https`, `codigo_https` e `restic_lab` são definidas no ficheiro de parâmetros. `teste_https` exige sucesso HTTP; `codigo_https` permite observar também os códigos de falha. Em cada tarefa, recolhe a evidência antes da intervenção e volta a testar o mesmo alvo depois.

### Distinguir comandos e conteúdo dos ficheiros

- Os blocos **`bash`** contêm comandos para executar no terminal da máquina indicada.
- Os blocos **`nginx`**, **`ini`**, **`html`** e de texto com conteúdo de ficheiros são para colar no editor aberto no passo anterior.
- Nos modelos, substitui todos os marcadores **`@…@`** pelos valores reais da cópia local de parâmetros. O editor não expande variáveis Bash. Para consultar um valor no terminal, usa, por exemplo, `printf '%s\n' "$NOME_SITE"`.
- Nos ficheiros Nginx, conserva **`$host`** e **`$request_uri`** exatamente como aparecem: são variáveis do Nginx, não marcadores a preencher.
- No nano, guarda com **Ctrl+O**, confirma com **Enter** e sai com **Ctrl+X**. Só depois executa o bloco Bash seguinte.
- Confirma que não ficaram marcadores por preencher antes de instalar ou validar a configuração.

Os comandos foram revistos documentalmente e quanto à sintaxe. Os resultados descritos abaixo são critérios de verificação; não representam execuções deste guia nas VMs da sala.

## Preparação CP4 — criar a base numa VM nova

**Contexto: VM do posto, antes de iniciar T0.**

1. Confirma Docker e Compose. Segue os blocos completos de [PREPARAR_CP4.md](../PREPARAR_CP4.md): criação do Compose, arranque, ficheiros iniciais e teste de persistência.
2. O modelo cria o projeto `cp4`, serviço `app` e volume `cp4_dados`. Se a aplicação já tiver sido instalada como referência, identifica-a e regista essa origem em vez de criar uma segunda base.
3. Confirma o caminho do ficheiro Compose em `COMPOSE_CP4`. Se seguiste o guia com a conta do formando, esse ficheiro está na pasta `cp4` da sua conta.
4. Obtém a localização real dos dados:

```bash
VOLUME_CP4_PATH=$(sudo docker volume inspect "$VOLUME_CP4" --format '{{.Mountpoint}}')
printf 'Volume: %s\nLocalização: %s\n' "$VOLUME_CP4" "$VOLUME_CP4_PATH"
sudo test -d "$VOLUME_CP4_PATH"
```

5. Regista esse caminho na cópia privada de parâmetros. Confirma a mesma origem no modelo do backup de T10.

**Resultado esperado:** HTTP funcional, ficheiros identificados no volume e dados preservados quando o contentor é recriado. Uma aplicação de referência fornecida pelo formador permite continuar a sessão, mas deve ser identificada como tal na evidência do formando.

## T0 — Arranque e verificação

**Contexto: VM do posto · 15 min · reposição às 08:45.**

1. Confirma o posto e o estado do sistema:

```bash
hostname
id
lsb_release -ds
uptime
sudo docker compose ls
sudo docker ps -a --filter label=com.docker.compose.project=cp4
```

2. Confirma o Compose atribuído e a montagem:

```bash
sudo docker compose -f "$COMPOSE_CP4" ps
CONTENTOR=$(sudo docker compose -f "$COMPOSE_CP4" ps -q app)
sudo docker inspect "$CONTENTOR" \
    --format '{{range .Mounts}}{{println .Name "->" .Destination}}{{end}}'
```

3. Testa a aplicação a partir da própria VM:

```bash
curl --retry 5 --retry-connrefused --retry-delay 1 --max-time 10 \
    --fail --silent --show-error "http://127.0.0.1:${PORTA_BACKEND}/"
curl --silent --output /dev/null --write-out '%{http_code}\n' \
    "http://127.0.0.1:${PORTA_BACKEND}/"
```

**Validar:** resposta `200`, conteúdo coerente e explicação de projeto, serviço, contentor e volume. O volume de dados não é a camada gravável do contentor.

**Se estiver parada:** consulta `sudo docker compose -f "$COMPOSE_CP4" logs --tail 50 app`, valida a configuração e executa `sudo docker compose -f "$COMPOSE_CP4" up -d`. Se estiver em falta, usa a preparação CP4. Não removas o volume para refazer o contentor.

## T1 — Decisão de proteção e restauro amostral

**Contexto: VM do posto · 30 min.**

### Decisão e respostas esperadas

- Conjuntos críticos: conteúdo do site, configuração/certificados e dados persistentes da aplicação. Aceitar outros conjuntos se forem pertinentes e justificados.
- RPO representa a perda de dados admissível em tempo; RTO representa o tempo pretendido para recuperar o serviço. Devem ser ligados à frequência, ao destino e ao procedimento de recuperação.
- Exemplo pedagógico: RPO de uma hora, cópias pelo menos horárias e RTO de quinze minutos para o pequeno serviço didático. Estes valores são uma proposta a justificar, não um SLA medido de produção.
- A cópia deve estar num destino separado e ter acessos recuperáveis. Um segundo disco da mesma VM não cobre a perda do anfitrião ou de todo o seu armazenamento.

### Restauro de uma amostra

Usa uma pasta nova para não sobrepor um ensaio anterior:

```bash
T1_DIR=$(mktemp -d "$HOME/t1-ensaio.XXXXXX")
sudo cp -a "$AMOSTRA_ORIGEM" "$T1_DIR/original"
sudo chown -R "$(id -u):$(id -g)" "$T1_DIR/original"

(cd "$T1_DIR/original" && find . -type f -exec sha256sum {} + | sort -k2) \
    > "$T1_DIR/hashes.txt"
wc -l "$T1_DIR/hashes.txt"
tar -C "$T1_DIR" -czf "$T1_DIR/amostra.tgz" original
tar -tzf "$T1_DIR/amostra.tgz"
```

Depois de confirmar que é apenas a cópia de trabalho, simula a perda e restaura:

```bash
test -n "$T1_DIR" && test -f "$T1_DIR/amostra.tgz" && test -d "$T1_DIR/original" && \
    rm -r -- "$T1_DIR/original"
tar -C "$T1_DIR" -xzf "$T1_DIR/amostra.tgz"
(cd "$T1_DIR/original" && sha256sum -c "$T1_DIR/hashes.txt")
```

**Validar:** todos os ficheiros verificados com `OK`, além da decisão justificada. Não aceitar apenas as últimas linhas da saída se houver ficheiros anteriores por conferir.

**Resposta à pergunta:** listar o arquivo confirma que pode ser lido e enumera entradas. A comparação após extração demonstra que o conteúdo restaurado coincide com a referência. A utilidade funcional dos dados exige ainda o teste adequado ao serviço.

## T2 — Baseline, carga e limiares

**Contexto: VM do posto · 30 min.**

1. Recolhe uma baseline com hora e unidade:

```bash
date --iso-8601=seconds
uptime
nproc
free -h
df -h /
df -i /
systemctl is-active docker
sudo ss -tlnp
curl --silent --output /dev/null \
    --write-out 'codigo=%{http_code} tempo=%{time_total}s\n' \
    "http://127.0.0.1:${PORTA_BACKEND}/"
top
```

Sai do `top` com `q`. Na folha, regista load average, CPU, memória disponível, disco/inodes e resposta HTTP. Não inventes valores de referência: usam-se os observados em cada posto.

2. Provoca carga limitada a noventa segundos, um processo por CPU:

```bash
PIDS_CARGA=()
for ((i=0; i<$(nproc); i++)); do
    timeout 90 sh -c 'exec yes > /dev/null' &
    PIDS_CARGA+=("$!")
done
```

3. Durante a carga, repete `uptime`, a observação no `top` e o teste HTTP. Depois confirma o fim:

```bash
wait "${PIDS_CARGA[@]}" || true
pgrep -a -x yes || true
```

**Esperado:** CPU mais ocupada e load average a subir; o impacto no HTTP depende dos recursos e deve ser observado. O load average mantém memória temporal das amostras de 1/5/15 minutos e não desce imediatamente quando os processos acabam.

**Exemplos de resposta, por adaptar:** CPU acima de 80% durante cinco minutos, severidade Warning, investigar processos e comparar com a baseline; falha de código/conteúdo HTTPS na recolha de um minuto, severidade High, confirmar origem e consultar serviço/logs. Não aceitar só «CPU > 80%» sem duração, contexto e ação.

## T3 — Publicar o site Nginx

**Contexto: VM do posto · 30 min · reposição às 10:35.**

1. Confirma o serviço e cria conteúdo identificável:

```bash
nginx -v
systemctl is-active nginx
sudo install -d -o root -g root -m 0755 "$WEB_ROOT"
sudo nano "$WEB_ROOT/index.html"
```

**Conteúdo de `index.html`:** substitui `@POSTO@` pelo identificador do posto.

```html
<h1>@POSTO@ - SITE-OK</h1>
```

Guarda e fecha o editor. Depois, no terminal, abre o ficheiro de estado:

```bash
sudo nano "$WEB_ROOT/estado.html"
```

**Conteúdo de `estado.html`:** substitui `@POSTO@` pelo identificador do posto.

```text
ESTADO-@POSTO@
```

Guarda e fecha o editor. Aplica as permissões no terminal:

```bash
sudo chmod 0644 "$WEB_ROOT/index.html" "$WEB_ROOT/estado.html"
```

2. Cria a configuração de trabalho:

```bash
CONF_TRABALHO="$HOME/site-${POSTO}.conf"

nano "$CONF_TRABALHO"
```

**Conteúdo do ficheiro `$CONF_TRABALHO`:** substitui os marcadores `@…@` pelos valores da cópia local de parâmetros.

```nginx
server {
    listen @PORTA_HTTP@;
    server_name @NOME_SITE@;
    root "@WEB_ROOT@";
    index index.html;
    access_log "@ACCESS_LOG@";
    error_log "@ERROR_LOG@";
}
```

Guarda o ficheiro e fecha o editor antes de executar os próximos comandos.

3. Guarda a configuração anterior, se existir, e aplica só com validação:

```bash
if sudo test -e "$NGINX_INCLUDE"; then
    sudo cp -a "$NGINX_INCLUDE" "${NGINX_INCLUDE}.antes-t3-$(date +%Y%m%d%H%M%S)"
fi
sudo install -o root -g root -m 0644 "$CONF_TRABALHO" "$NGINX_INCLUDE"
sudo nginx -t && sudo systemctl reload nginx
```

4. Verifica com nome e destino explícitos:

```bash
teste_http
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' \
    --resolve "${NOME_SITE}:${PORTA_HTTP}:${IP_VM}" \
    "http://${NOME_SITE}:${PORTA_HTTP}/estado.html"
```

**Esperado:** `ESTADO-` seguido do posto e código `200`. Pode ser necessário aguardar um ou dois segundos após o reload e repetir. Confirma que o ficheiro dedicado está num diretório incluído no contexto `http`; usa `sudo nginx -T` para inspecionar a configuração efetiva.

**Resposta:** um pedido por IP envia um nome diferente do configurado; pode selecionar o servidor por omissão dessa porta. A evidência precisa do nome correto e do marcador do posto.

## T4 — Permissões e exposição

**Contexto: VM do posto · 20 min.**

1. Identifica a conta dos workers e testa os acessos:

```bash
ps -o user=,args= -C nginx
WORKER=$(ps -o user=,args= -C nginx | awk '/worker process/ {print $1; exit}')
printf 'Conta de serviço: %s\n' "$WORKER"
namei -l "$WEB_ROOT/estado.html"
if [[ -z "$WORKER" ]]; then
    echo 'Não foi identificada uma conta de worker: verificar o Nginx.'
else
    sudo -u "$WORKER" test -r "$WEB_ROOT/estado.html" && echo 'Leitura permitida'
    if sudo -u "$WORKER" test -w "$WEB_ROOT/estado.html"; then
        echo 'Escrita permitida: corrigir'
    else
        echo 'Escrita negada'
    fi
fi
```

Se `WORKER` ficar vazio, resolve o estado do Nginx antes dos testes de identidade. Para o conteúdo criado neste percurso, o estado de referência é dono `root:root`, diretório `0755` e ficheiros `0644`:

```bash
sudo chown root:root "$WEB_ROOT" "$WEB_ROOT/index.html" "$WEB_ROOT/estado.html"
sudo chmod 0755 "$WEB_ROOT"
sudo chmod 0644 "$WEB_ROOT/index.html" "$WEB_ROOT/estado.html"
```

2. Mantém SSH e recolha do agente; abre HTTP/HTTPS para a rede atribuída:

```bash
sudo ufw status numbered
sudo ufw allow OpenSSH
sudo ufw allow from "$IP_ZABBIX" to any port 10050 proto tcp
sudo ufw allow from "$REDE_LAB" to any port "$PORTA_HTTP" proto tcp
sudo ufw allow from "$REDE_LAB" to any port "$PORTA_HTTPS" proto tcp
sudo ufw --force enable
sudo ufw status numbered
teste_http
```

**Validar:** leitura sim, escrita não e página funcional. A regra do agente deve limitar a origem ao servidor Zabbix; verifica se não ficou uma regra anterior mais ampla. Não faças reset da firewall nem retires a regra de recuperação SSH.

## T5 — HTTPS com a CA existente

**Contextos: VM do posto e máquina do formador · 40 min · reposição às 11:15.**

### A. Na VM do posto: chave e CSR

```bash
sudo install -d -o root -g root -m 0700 "$DIR_TLS"
```

Se já existir uma chave deste site, o bloco conserva-a e cria apenas um CSR novo. Se estiver em falta, gera a chave e o CSR:

```bash
if sudo test -e "$DIR_TLS/$NOME_SITE.key"; then
    sudo openssl req -new -key "$DIR_TLS/$NOME_SITE.key" \
        -out "$HOME/$NOME_SITE.csr" -subj "/CN=$NOME_SITE" \
        -addext "subjectAltName=DNS:$NOME_SITE"
else
    sudo openssl req -new -newkey rsa:3072 -nodes \
        -keyout "$DIR_TLS/$NOME_SITE.key" -out "$HOME/$NOME_SITE.csr" \
        -subj "/CN=$NOME_SITE" -addext "subjectAltName=DNS:$NOME_SITE"
fi
sudo chmod 0600 "$DIR_TLS/$NOME_SITE.key"
sudo chown "$(id -u):$(id -g)" "$HOME/$NOME_SITE.csr"
openssl req -in "$HOME/$NOME_SITE.csr" -noout -subject -text
```

O CSR é enviado ao formador. A chave privada do servidor permanece na VM.

### B. Na máquina do formador / Proxmox: assinar

Carrega a cópia privada de parâmetros dessa máquina. `CA_CERT_FORMADOR` e `CA_CHAVE_FORMADOR` têm de apontar para **a mesma CA que já foi distribuída aos postos**. Não cries outra CA para resolver uma emissão em falta.

```bash
PEDIDOS="$HOME/pedidos-certificados-$POSTO"
install -d -m 0700 "$PEDIDOS"
scp -i "$CHAVE_SSH_FORMADOR" \
    "$ALUNO@$IP_VM:/home/$ALUNO/$NOME_SITE.csr" "$PEDIDOS/"
openssl req -in "$PEDIDOS/$NOME_SITE.csr" -noout -verify
openssl req -in "$PEDIDOS/$NOME_SITE.csr" -noout -subject -text
openssl x509 -in "$CA_CERT_FORMADOR" -noout -subject -dates
```

Confirma o posto e o SAN. Emite apenas para o nome atribuído, usando extensões definidas pelo formador:

```bash
nano "$PEDIDOS/extensoes.cnf"
```

**Conteúdo do ficheiro `$PEDIDOS/extensoes.cnf`:** substitui os marcadores `@…@` pelos valores da cópia local de parâmetros.

```ini
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:@NOME_SITE@
```

Guarda o ficheiro e fecha o editor antes de executar os próximos comandos.

```bash
openssl x509 -req -in "$PEDIDOS/$NOME_SITE.csr" \
    -CA "$CA_CERT_FORMADOR" -CAkey "$CA_CHAVE_FORMADOR" -CAcreateserial \
    -out "$PEDIDOS/$NOME_SITE.crt" -days 30 -sha256 \
    -extfile "$PEDIDOS/extensoes.cnf"
openssl verify -CAfile "$CA_CERT_FORMADOR" "$PEDIDOS/$NOME_SITE.crt"
scp -i "$CHAVE_SSH_FORMADOR" "$PEDIDOS/$NOME_SITE.crt" \
    "$ALUNO@$IP_VM:/home/$ALUNO/"
```

### C. Na VM do posto: inspecionar, instalar e aplicar

```bash
openssl x509 -in "$HOME/$NOME_SITE.crt" \
    -noout -subject -issuer -dates -ext subjectAltName
openssl verify -CAfile "$CA_CERT" "$HOME/$NOME_SITE.crt"
sudo install -o root -g root -m 0644 "$HOME/$NOME_SITE.crt" "$DIR_TLS/$NOME_SITE.crt"
sudo cp -a "$NGINX_INCLUDE" "${NGINX_INCLUDE}.antes-t5-$(date +%Y%m%d%H%M%S)"

nano "$HOME/site-${POSTO}.conf"
```

**Conteúdo do ficheiro `$HOME/site-${POSTO}.conf`:** substitui os marcadores `@…@` pelos valores da cópia local de parâmetros.

```nginx
server {
    listen @PORTA_HTTP@;
    server_name @NOME_SITE@;
    return 301 https://$host:@PORTA_HTTPS@$request_uri;
}
server {
    listen @PORTA_HTTPS@ ssl;
    server_name @NOME_SITE@;
    ssl_certificate "@DIR_TLS@/@NOME_SITE@.crt";
    ssl_certificate_key "@DIR_TLS@/@NOME_SITE@.key";
    root "@WEB_ROOT@";
    index index.html;
    access_log "@ACCESS_LOG@";
    error_log "@ERROR_LOG@";
}
```

Guarda o ficheiro e fecha o editor antes de executar os próximos comandos.

```bash
sudo install -o root -g root -m 0644 "$HOME/site-${POSTO}.conf" "$NGINX_INCLUDE"
sudo nginx -t && sudo systemctl reload nginx
```

4. Verifica cadeia, nome, prazo, conteúdo e redireção:

```bash
teste_https
codigo_https
curl --silent --show-error --head \
    --resolve "${NOME_SITE}:${PORTA_HTTP}:${IP_VM}" \
    "http://${NOME_SITE}:${PORTA_HTTP}/"
openssl s_client -connect "$IP_VM:$PORTA_HTTPS" -servername "$NOME_SITE" \
    -CAfile "$CA_CERT" -verify_hostname "$NOME_SITE" -verify_return_error </dev/null
```

**Esperado:** marcador correto, HTTPS `200`, HTTP `301`, nome/SAN correto, certificado dentro do prazo e verificação TLS bem-sucedida. Não aceitar validação com `-k` ou `--insecure`. As opções de nome e de erro de verificação do cliente estão descritas em [openssl s_client](https://docs.openssl.org/3.5/man1/openssl-s_client/).

**Resposta:** um certificado emitido só para o nome DNS não valida um pedido feito para o IP. O SNI também participa na seleção do servidor HTTPS. A chave privada tem de estar protegida e legível pelo processo master do Nginx. [Referência Nginx](https://nginx.org/en/docs/http/configuring_https_servers.html)

## T6 — Duas falhas web e extensão

**Contexto: VM do posto, intervenção do formador · 30 min · reposição às 11:45.**

Antes de cada falha, confirma o HTTPS saudável. Introduz a seguinte apenas depois de validar a anterior.

### Falha 1: ficheiro sem leitura para o serviço

Injeção pelo formador:

```bash
sudo chmod 0600 "$WEB_ROOT/estado.html"
codigo_https
```

**Sintoma esperado:** `403` no ficheiro de estado. A página inicial pode continuar a funcionar.

Diagnóstico e resolução:

```bash
sudo tail -n 20 "$ERROR_LOG"
namei -l "$WEB_ROOT/estado.html"
sudo chmod 0644 "$WEB_ROOT/estado.html"
teste_https
codigo_https
```

**Evidência:** erro de acesso negado no log e modo `0600`; recuperação com `0644`, código `200` e conteúdo correto. Não é necessário reiniciar a VM nem recriar o site.

### Falha 2: raiz incorreta

1. Guarda a configuração saudável e abre o ficheiro dedicado:

```bash
sudo cp -a "$NGINX_INCLUDE" "${NGINX_INCLUDE}.antes-t6-2"
sudoedit "$NGINX_INCLUDE"
```

2. No bloco HTTPS, altera apenas `root` para um caminho inexistente, mantendo a sintaxe. Valida e aplica:

```bash
sudo nginx -t && sudo systemctl reload nginx
codigo_https
```

**Sintoma esperado:** `404`. O log aponta para um recurso no diretório inexistente.

3. O formando deve relacionar o caminho do log com a configuração efetiva:

```bash
sudo tail -n 20 "$ERROR_LOG"
sudo nginx -T
```

4. Corrige apenas `root` para `WEB_ROOT`, valida e aplica. Para reversão imediata pelo formador, repõe a cópia saudável:

```bash
sudo cp -a "${NGINX_INCLUDE}.antes-t6-2" "$NGINX_INCLUDE"
sudo nginx -t && sudo systemctl reload nginx
teste_https
```

### Extensão: reverse proxy e erro 502

No bloco HTTPS, acrescenta uma localização com o percurso atribuído. No modelo didático, usa-se `/app/`:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:8000/;
}
```

Adapta a porta ao `PORTA_BACKEND` confirmado. Aplica com `nginx -t` e testa `teste_https /app/`. Quando estiver funcional:

```bash
sudo docker compose -f "$COMPOSE_CP4" stop app
codigo_https /app/
sudo tail -n 20 "$ERROR_LOG"
sudo docker compose -f "$COMPOSE_CP4" up -d app
```

**Esperado:** `502` enquanto o backend estiver parado, com indicação de ligação recusada no log; recuperação após o arranque do backend. Aguarda o arranque e repete `teste_https /app/` até confirmar o conteúdo. Preserva os dados do volume.

**Validar T6:** em cada falha há sintoma, evidência concreta, hipótese, teste, correção mínima e reteste. Não aceitar como diagnóstico apenas «reiniciei e ficou bom».

## T7 — Primeiro backup com Restic

**Contexto: VM do posto · 45 min.**

1. Confirma a ferramenta, a origem CP4 e o disco de destino:

```bash
command -v restic
restic version
VOLUME_CP4_PATH=$(sudo docker volume inspect "$VOLUME_CP4" --format '{{.Mountpoint}}')
sudo test -d "$VOLUME_CP4_PATH"
findmnt "$PONTO_REPO"
mountpoint -q "$PONTO_REPO"
```

Se o destino previsto não estiver montado, corrige a preparação antes de criar o repositório. Este percurso usa três origens: conteúdo web, `/etc/nginx` e volume CP4. `DIR_TLS` deve estar dentro da configuração Nginx, como é verificado no modelo de parâmetros.

2. Prepara o ficheiro de segredo sem o mostrar no ecrã. Não substituas o segredo de um repositório existente:

```bash
(
    set -eo pipefail
    if sudo test -f "$REPO/config" && ! sudo test -s "$PWFILE"; then
        echo 'Repositório existente sem segredo disponível: recuperar a cópia de custódia.' >&2
        exit 1
    fi
    if ! sudo test -e "$PWFILE"; then
        sudo install -o root -g root -m 0600 /dev/null "$PWFILE"
        openssl rand -base64 32 | sudo tee "$PWFILE" >/dev/null
    fi
    sudo chown root:root "$PWFILE"
    sudo chmod 0600 "$PWFILE"
    sudo test -s "$PWFILE"
)
```

Conserva uma cópia de custódia pelo canal preparado pelo formador. Regista apenas a referência dessa custódia na folha, nunca o valor.

3. Inicializa, se for um repositório novo, e faz o backup:

```bash
sudo install -d -o root -g root -m 0700 "$REPO"
if ! sudo test -f "$REPO/config"; then
    restic_lab init
fi

restic_lab backup "$WEB_ROOT" /etc/nginx "$VOLUME_CP4_PATH" --tag sessao-final
restic_lab snapshots
restic_lab ls latest
restic_lab check
```

**Validar:** ID do snapshot registado, três conjuntos visíveis e `check` sem erros. Os dados CP4 deste ensaio são ficheiros didáticos; um serviço com base de dados exigiria um procedimento de consistência próprio.

**Resposta:** o `check` verifica a estrutura e a consistência do repositório; sem leitura integral dos dados não examina todos os blocos. Mesmo uma verificação completa não substitui o restauro e a validação funcional de T11.

## T8 — Proteção do repositório

**Contexto: VM do posto, como utilizador comum com sudo · 15 min.**

1. Confirma donos/permissões e testa o acesso sem elevação:

```bash
id
sudo ls -ld "$PONTO_REPO" "$REPO"
sudo ls -l "$PWFILE"
if test -r "$PWFILE"; then
    echo 'O utilizador comum consegue ler o segredo: corrigir'
else
    echo 'Leitura do segredo negada ao utilizador comum'
fi
ls "$REPO"
```

**Esperado:** dono administrativo, segredo `0600`, acesso negado ao utilizador comum. Este teste não deve ser executado numa shell root: o root é a identidade administrativa que tem de conseguir recuperar o backup.

2. Verifica que um segredo errado é recusado:

```bash
PW_ERRADA=$(mktemp "$HOME/pw-errada.XXXXXX")
printf '%s\n' 'palavra-passe-incorreta-de-ensaio' > "$PW_ERRADA"
sudo restic --repo "$REPO" --password-file "$PW_ERRADA" snapshots
RESULTADO_ERRADO=$?
printf 'Código de saída com segredo errado: %s\n' "$RESULTADO_ERRADO"
rm -- "$PW_ERRADA"
```

**Esperado:** código diferente de zero e falha de abertura. Confirma depois que `restic_lab snapshots` continua a funcionar com o ficheiro correto.

**Resposta:** a encriptação e as permissões limitam o acesso, mas não criam outra cópia. Se o disco/VM/armazenamento que contém origem e repositório se perder, a recuperação depende de uma cópia noutra localização e de credenciais em custódia separada.

## T9 — Retenção simulada

**Contexto: VM do posto · 15 min.**

1. Cria mais dois snapshots do mesmo conjunto de caminhos:

```bash
printf 'versao 2 - %s\n' "$(date --iso-8601=seconds)" | sudo tee -a "$WEB_ROOT/index.html" >/dev/null
restic_lab backup "$WEB_ROOT" /etc/nginx "$VOLUME_CP4_PATH" --tag sessao-final
printf 'versao 3 - %s\n' "$(date --iso-8601=seconds)" | sudo tee -a "$WEB_ROOT/index.html" >/dev/null
restic_lab backup "$WEB_ROOT" /etc/nginx "$VOLUME_CP4_PATH" --tag sessao-final
restic_lab snapshots --tag sessao-final
```

2. Pede a previsão antes de simular:

```bash
restic_lab forget --dry-run --tag sessao-final --keep-last 2
restic_lab forget --dry-run --tag sessao-final --keep-daily 7 --keep-weekly 4
```

**Resposta de referência:** com exatamente três snapshots do mesmo host/caminhos, todos criados hoje, `keep-last 2` mantém os dois mais recentes. No ensaio documentado com Restic 0.18.1, a política diária/semanal manteve dois: o mais recente e o mais antigo, identificado nos motivos de retenção. Lê sempre a saída `Reasons`; não generalizes o número se houver outro histórico, grupos ou versão.

As regras são aplicadas por grupos e pelo histórico disponível, não criam snapshots de dias em falta. A sessão usa apenas `--dry-run`; `forget` sem essa opção e `prune` ficam fora do exercício. [Retenção no Restic 0.18.1](https://restic.readthedocs.io/en/v0.18.1/060_forget.html)

## T10 — Automatizar com systemd timer

**Contexto: VM do posto · 25 min.**

1. Confirma executável, origem CP4 e calendário:

```bash
RESTIC=$(command -v restic)
VOLUME_CP4_PATH=$(sudo docker volume inspect "$VOLUME_CP4" --format '{{.Mountpoint}}')
systemd-analyze calendar "$CALENDARIO"
```

2. Cria os modelos com os valores do posto:

```bash
nano "$HOME/backup-sessao.service"
```

**Conteúdo do ficheiro `$HOME/backup-sessao.service`:** substitui os marcadores `@…@` pelos valores da cópia local de parâmetros.

```ini
[Unit]
Description=Backup Restic - sessao final
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=@RESTIC@ --repo "@REPO@" --password-file "@PWFILE@" backup "@WEB_ROOT@" /etc/nginx "@VOLUME_CP4_PATH@" --tag sessao-final --tag timer
```

Guarda o ficheiro e fecha o editor antes de executar os próximos comandos.

```bash
nano "$HOME/backup-sessao.timer"
```

**Conteúdo do ficheiro `$HOME/backup-sessao.timer`:** substitui os marcadores `@…@` pelos valores da cópia local de parâmetros.

```ini
[Unit]
Description=Agendamento do backup Restic - sessao final

[Timer]
OnCalendar=@CALENDARIO@
Persistent=true

[Install]
WantedBy=timers.target
```

Guarda o ficheiro e fecha o editor antes de executar os próximos comandos.

```bash
sudo install -o root -g root -m 0644 "$HOME/backup-sessao.service" /etc/systemd/system/backup-sessao.service
sudo install -o root -g root -m 0644 "$HOME/backup-sessao.timer" /etc/systemd/system/backup-sessao.timer
sudo systemd-analyze verify /etc/systemd/system/backup-sessao.service /etc/systemd/system/backup-sessao.timer
sudo systemctl daemon-reload
sudo systemctl enable --now backup-sessao.timer
sudo systemctl start backup-sessao.service
```

3. Demonstra agendamento e execução:

```bash
systemctl list-timers --all backup-sessao.timer
systemctl show backup-sessao.service -p Result -p ExecMainStatus
sudo journalctl -u backup-sessao.service -n 30 --no-pager
restic_lab snapshots --tag timer
```

**Esperado:** próxima execução prevista, `Result=success`, `ExecMainStatus=0` e snapshot novo com a etiqueta `timer`. Um serviço `oneshot` pode regressar a inativo depois de terminar; isso não significa que o backup falhou.

**Resposta:** timer ativo comprova agendamento; journal e snapshot comprovam a execução do backup. A recuperação funcional continua por demonstrar em T11.

## T11 — Restauro controlado

**Contexto: VM do posto · 35 min · reposição às 15:00.**

1. Cria o ficheiro de teste, faz backup e escolhe explicitamente o snapshot:

```bash
printf 'RESTAURO-%s-%s\n' "$POSTO" "$(date --iso-8601=seconds)" \
    | sudo tee "$WEB_ROOT/teste-restauro.html" >/dev/null
restic_lab backup "$WEB_ROOT" --tag teste-restauro
restic_lab snapshots --tag teste-restauro
read -r -p 'ID do snapshot que acabaste de criar: ' ID_TESTE
```

Regista o ID na folha. Confirma que esse snapshot contém o ficheiro antes de simular a perda:

```bash
restic_lab ls "${ID_TESTE:?Indicar o ID do snapshot}" "$WEB_ROOT/teste-restauro.html"
```

2. Simula a perda apenas do ficheiro de teste e mede o início:

```bash
INICIO_RESTAURO=$(date +%s)
date --iso-8601=seconds
sudo rm -- "$WEB_ROOT/teste-restauro.html"
codigo_https /teste-restauro.html
```

**Esperado:** `404`. Não elimines o site nem a configuração.

3. Restaura para uma área privada nova:

```bash
STAGING=$(sudo mktemp -d /tmp/adm-restauro.XXXXXX)
restic_lab restore "${ID_TESTE:?Indicar o ID do snapshot}" \
    --target "$STAGING" --include "$WEB_ROOT/teste-restauro.html"
sudo stat "$STAGING$WEB_ROOT/teste-restauro.html"
sudo cat "$STAGING$WEB_ROOT/teste-restauro.html"
```

O caminho absoluto original aparece abaixo do destino de staging. A opção `--include` limita os dados extraídos; não restaura diretamente sobre a origem. [Restauro seletivo no Restic](https://restic.readthedocs.io/en/stable/050_restore.html)

4. Compara o conteúdo com o registo e promove apenas o ficheiro pretendido:

```bash
sudo install -o root -g root -m 0644 \
    "$STAGING$WEB_ROOT/teste-restauro.html" "$WEB_ROOT/teste-restauro.html"
if teste_https /teste-restauro.html; then
    FIM_RESTAURO=$(date +%s)
    date --iso-8601=seconds
    printf 'Tempo observado de recuperação: %s segundos\n' "$((FIM_RESTAURO-INICIO_RESTAURO))"
fi
codigo_https /teste-restauro.html
```

5. Depois de validar, limpa apenas a pasta temporária criada neste ensaio:

```bash
case "$STAGING" in
    /tmp/adm-restauro.??????) sudo rm -rf -- "$STAGING" ;;
    *) echo 'Caminho de staging inesperado: confirmar antes de limpar.' ;;
esac
```

**Validar:** conteúdo original recuperado, `200`, hora final e comparação com o RTO de T1. Este ensaio reduzido não demonstra por si um RTO de recuperação integral da infraestrutura.

## T12 — Host no Zabbix

**Contextos: VM do posto e browser do Windows · 25 min.**

1. Na VM do posto, confirma o agente e a exposição:

```bash
zabbix_agent2 -V
systemctl is-active zabbix-agent2
sudo ss -ltnp 'sport = :10050'
sudo ufw status
```

2. No browser, entra no frontend com a conta do posto. Vai a **Data collection → Hosts → Create host** e preenche:

| Campo | Valor |
|---|---|
| Host name | Valor de `NOME_LOGICO_DO_POSTO` |
| Templates | `Linux by Zabbix agent`, variante passiva |
| Host groups | Valor de `GRUPO_HOSTS` |
| Interfaces → Agent | `IP_VM`, porta 10050, ligação por IP |
| Encryption → Connections to host | PSK |
| PSK identity | Valor de `IDENTIFICADOR_PUBLICO` |
| PSK | Segredo entregue pelo canal privado do formador |

3. Grava, espera uma ou duas recolhas e consulta **Monitoring → Latest data**, filtrando pelo host.

**Validar:** disponibilidade do agente a verde e valores recentes de CPU, memória, disco e uptime. Regista item, unidade e instante; um valor antigo não comprova recolha atual.

### Se o agente ficar vermelho

- Passa o rato no indicador ZBX e lê o erro.
- Confirma endereço/interface e template passivo.
- Na VM, verifica `Server`, `Hostname`, `TLSAccept`, `TLSPSKIdentity` e a referência ao ficheiro PSK. Não mostres o conteúdo do segredo em capturas.
- Confirma a firewall e o acesso apenas a partir do servidor Zabbix.
- Consulta os logs do agente. A mensagem `cannot accept unencrypted connection` aponta para a ligação deixada sem PSK no frontend.

```bash
sudo journalctl -u zabbix-agent2 --since '-15 min' --no-pager
```

Se a instalação usar um ficheiro de log próprio, consulta também esse destino. Para testar diretamente, **na VM Zabbix**, com os parâmetros privados e a cópia correta do segredo:

```bash
sudo zabbix_get -s "$IP_VM" -k agent.ping \
    --tls-connect psk --tls-psk-identity "$IDENTIFICADOR_PUBLICO" \
    --tls-psk-file "$PSK_TESTE_ZABBIX"
```

**Esperado:** `1`. Este teste é complementar à observação de métricas recentes no frontend. [PSK no Zabbix 7.0](https://www.zabbix.com/documentation/7.0/en/manual/encryption/using_pre_shared_keys)

## T13 — Cenário HTTPS e triggers

**Contextos: VM Zabbix e browser do Windows · 25 min · reposição às 15:50.**

### A. Confirmar o pedido a partir do servidor que o vai executar

Na VM Zabbix, confirma que o nome do site resolve para o posto e que a CA preparada está instalada como confiável:

```bash
getent hosts "$NOME_SITE"
curl --fail --silent --show-error --max-time 10 \
    "https://${NOME_SITE}:${PORTA_HTTPS}/estado.html"
```

Se o nome não resolver corretamente, revê apenas a entrada correspondente em `/etc/hosts` ou o registo DNS preparado. A linha tem o endereço do posto e o nome atribuído, separados por espaço. Repete `getent hosts` e confirma o destino.

Se a CA não for reconhecida, copia o **certificado público** da CA já usada na sessão. Na **máquina do formador / Proxmox**:

```bash
scp -i "$CHAVE_SSH_FORMADOR" "$CA_CERT_FORMADOR" \
    "$ALUNO@$IP_ZABBIX:/home/$ALUNO/ca-lab.crt"
```

Na **VM Zabbix**, instala-o no armazém de confiança e repete o pedido:

```bash
sudo install -o root -g root -m 0644 "$HOME/ca-lab.crt" \
    /usr/local/share/ca-certificates/ca-lab.crt
sudo update-ca-certificates
curl --fail --silent --show-error --max-time 10 \
    "https://${NOME_SITE}:${PORTA_HTTPS}/estado.html"
```

A chave privada da CA permanece na máquina do formador. O nome deve estar resolvido no servidor Zabbix; um `--resolve` usado apenas no PC não corrige a resolução do cenário.

### B. Criar o cenário no frontend

1. Em **Data collection → Hosts**, abre os cenários **Web** do host do posto.
2. Seleciona **Create web scenario**.
3. Nome: `HTTPS-` seguido do posto; intervalo: `1m`.
4. Em **Steps → Add**, usa nome `estado`, URL HTTPS do ficheiro `estado.html`, código exigido `200` e texto obrigatório `ESTADO-` seguido do posto.
5. Ativa **SSL verify peer** e **SSL verify host** depois de confirmar a confiança na CA. Se uma limitação obrigar a desligar a verificação no ensaio, regista que só ficou demonstrada disponibilidade/conteúdo, não a confiança TLS.
6. Guarda e confirma amostras recentes do cenário. O item **Failed step** deve ser `0` quando o serviço está saudável.

Os pedidos do cenário são executados pelo servidor/proxy Zabbix. A confiança na CA e a verificação do nome têm de funcionar nesse contexto. [Monitorização web no Zabbix 7.0](https://www.zabbix.com/documentation/7.0/en/manual/web_monitoring)

### C. Trigger do site

1. Nos triggers do host, usa **Create trigger** no canto superior direito; não confundas o formulário de criação com o filtro da lista.
2. Nome: `Site <posto> indisponível`; severidade: **High**.
3. Adapta a expressão ao nome **exato** do host e do cenário:

```text
last(/<NOME_LOGICO_DO_POSTO>/web.test.fail[HTTPS-<POSTO>])<>0
```

4. Guarda e confirma o estado OK antes de provocar uma falha.

### D. Trigger de um limiar de T2

1. Em **Latest data**, identifica o item real que corresponde ao indicador escolhido. Confirma a unidade e o significado: utilização e percentagem de CPU idle têm sentidos diferentes.
2. Cria outro trigger e usa **Add** no construtor de expressões para selecionar esse item.
3. Para um exemplo de **utilização CPU > 80% durante cinco minutos**, pode usar-se o mínimo observado na janela acima de 80. Só se aplica se o item real medir utilização em percentagem:

```text
min(/<HOST>/<CHAVE_REAL_DO_ITEM>,5m)>80
```

Se o critério aprovado for uma média na janela, usa a função correspondente e explica a diferença. Confirma a frequência e a presença de amostras recentes: a janela da função não prova continuidade entre recolhas nem deve ser avaliada como cinco minutos de dados completos quando só chegou uma amostra. Não inventes a chave nem cries um trigger sem dados para satisfazer a checklist.

**Validar:** dois triggers, cenário com dados e correspondência entre o limiar escrito em T2 e a condição implementada. [Expressões no Zabbix 7.0](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/expression)

## T14 — Falha e recuperação observadas

**Contextos: VM do posto e browser do Windows · 25 min.**

1. Na VM do posto, regista a hora e provoca a paragem:

```bash
date --iso-8601=seconds
sudo systemctl stop nginx
```

2. Em **Monitoring → Problems**, observa o problema do site. Regista a hora do evento, o host e o seu identificador. O intervalo de um minuto e o momento da recolha explicam parte do atraso.
3. Repõe o serviço e regista o instante:

```bash
sudo systemctl start nginx
date --iso-8601=seconds
teste_https
codigo_https
```

4. No frontend, confirma uma amostra nova saudável e o evento **RESOLVED**. Regista os quatro instantes pedidos na folha.

**Resposta:** um evento na interface não comprova uma notificação entregue. Para demonstrar entrega seriam necessárias ação, meio/destinatário configurados e evidência da execução e receção. Esta sessão pode demonstrar PROBLEM/RESOLVED sem entrega de mensagens.

## T15 — Logs e correlação

**Contexto: VM do posto e browser do Windows · 20 min.**

1. Localiza os eventos no período da tarefa:

```bash
sudo journalctl -u nginx --since '-30 min' --no-pager
sudo tail -n 30 "$ACCESS_LOG"
sudo tail -n 30 "$ERROR_LOG"
sudo journalctl -u ssh --since today --no-pager
```

2. Seleciona a paragem/arranque do Nginx, um pedido do cenário Zabbix e um acesso SSH. Em Ubuntu, a unidade do serviço SSH é normalmente `ssh`.
3. Junta uma observação de monitorização, como **Failed step**, código de resposta ou evento com hora, às observações dos logs.

**Validar:** pelo menos três evidências pertinentes de duas famílias — monitorização e logs — com alvo, fonte, consulta, instante/fuso e interpretação. Três excertos de logs, por si só, não cumprem a presença da família de monitorização.

**Resposta de referência:** o journal mostra a transição do processo; o access log mostra pedidos e respostas; o Zabbix mostra a perspetiva da recolha do serviço. São observações complementares. Distinguir a hora da ocorrência/amostra da hora em que se abriu a interface.

## T16 — Incidente integrado

**Contextos: intervenção do formador na VM do posto; diagnóstico pelo formando · 40 min.**

Escolhe um cenário por posto. Confirma o serviço saudável, snapshot utilizável, acesso ao segredo e possibilidade de reversão antes de introduzir a falha. Dá uma pista às 17:05 se necessário; às 17:10, repõe o serviço e analisa o raciocínio em conjunto.

### Cenário A — Permissão do diretório

Injeção:

```bash
sudo chmod 0700 "$WEB_ROOT"
codigo_https
```

**Esperado:** `403`, erro de acesso negado e ausência de travessia para a conta de serviço.

Resolução e reversão:

```bash
namei -l "$WEB_ROOT/estado.html"
sudo tail -n 20 "$ERROR_LOG"
sudo chmod 0755 "$WEB_ROOT"
teste_https
```

**Backup necessário?** Não: os dados continuam presentes; a causa é a permissão do diretório. Restaurar conteúdo não é a ação mínima.

### Cenário B — Configuração inválida

Guarda uma cópia íntegra e introduz deliberadamente uma diretiva inexistente:

```bash
sudo cp -a "$NGINX_INCLUDE" "${NGINX_INCLUDE}.antes-t16b"
sudo nano "$NGINX_INCLUDE"
```

**Linha a acrescentar no fim do ficheiro de configuração:**

```nginx
directiva_invalida on;
```

Guarda e fecha o editor. A diretiva é inválida de propósito. No terminal, tenta reiniciar o serviço:

```bash
sudo systemctl restart nginx
```

O restart deve falhar neste cenário. **Esperado:** serviço indisponível, configuração rejeitada e mensagem com nome do ficheiro e linha.

Diagnóstico:

```bash
systemctl status nginx --no-pager
sudo journalctl -u nginx --since '-10 min' --no-pager
sudo nginx -t
```

**Ação mínima do formando:** remover apenas a diretiva inválida, validar e iniciar. Para reversão imediata pelo formador:

```bash
sudo cp -a "${NGINX_INCLUDE}.antes-t16b" "$NGINX_INCLUDE"
sudo nginx -t && sudo systemctl start nginx
teste_https
```

**Backup necessário?** Não necessariamente: a alteração pontual é identificável e a configuração anterior foi conservada.

### Cenário C — Conteúdo perdido e restauro

Antes da injeção, seleciona um snapshot de T7–T10 que contenha o ficheiro de estado. Não uses por engano o snapshot de T11 que só contém o ficheiro de teste.

```bash
restic_lab snapshots --tag sessao-final
read -r -p 'ID de um snapshot que contenha o ficheiro de estado: ' ID_INCIDENTE
restic_lab ls "${ID_INCIDENTE:?Indicar o snapshot}" "$WEB_ROOT/estado.html"
```

Depois de conferir o ficheiro e os acessos de recuperação, o formador simula a perda:

```bash
sudo rm -- "$WEB_ROOT/estado.html"
codigo_https
```

**Esperado:** `404` ou falha do texto obrigatório no cenário; log de ficheiro inexistente.

Resolução:

```bash
sudo tail -n 20 "$ERROR_LOG"
STAGING_INCIDENTE=$(sudo mktemp -d /tmp/adm-incidente.XXXXXX)
restic_lab restore "${ID_INCIDENTE:?Indicar o snapshot}" \
    --target "$STAGING_INCIDENTE" --include "$WEB_ROOT/estado.html"
sudo cat "$STAGING_INCIDENTE$WEB_ROOT/estado.html"
sudo stat "$STAGING_INCIDENTE$WEB_ROOT/estado.html"
```

Confirma o marcador do posto e só depois promove:

```bash
sudo install -o root -g root -m 0644 \
    "$STAGING_INCIDENTE$WEB_ROOT/estado.html" "$WEB_ROOT/estado.html"
teste_https
codigo_https
```

**Backup necessário?** Sim, neste cenário o formando deve exercitar o percurso de recuperação do conteúdo perdido. Se for preciso um desbloqueio pelo formador, pode ser fornecida uma cópia de referência identificada; isso deve ficar registado como apoio.

### Validação comum aos três cenários

1. O relatório apresenta pelo menos duas hipóteses e um teste que as distingue.
2. As evidências antecedem a correção e indicam fonte, alvo e instante.
3. O serviço responde de forma funcional com nome, CA e conteúdo corretos.
4. Há uma amostra nova saudável e recuperação correspondente no Zabbix; não basta um valor antigo ou reconhecer o evento.
5. A necessidade ou dispensa do backup está justificada pela causa.
6. A medida preventiva é coerente: revisão de permissões; teste antes de aplicar configurações; backup e controlo de alterações de conteúdo, conforme o caso.

Depois de validar o cenário C, limpa apenas o staging criado:

```bash
case "${STAGING_INCIDENTE:-}" in
    /tmp/adm-incidente.??????) sudo rm -rf -- "$STAGING_INCIDENTE" ;;
    *) echo 'Sem staging de incidente reconhecido para limpar.' ;;
esac
```

## T17 — Fecho e entrega

**Contextos: VM do posto, browser do Windows e registo do formador · 15 min.**

1. Desativa o agendamento de treino e confirma o estado:

```bash
sudo systemctl disable --now backup-sessao.timer
systemctl is-enabled backup-sessao.timer
systemctl is-active backup-sessao.timer
```

**Esperado:** `disabled` e `inactive`. Os comandos de consulta podem devolver código diferente de zero precisamente porque o timer já não está ativo.

2. Confirma o estado funcional final:

```bash
sudo nginx -t
systemctl is-active nginx
systemctl is-active zabbix-agent2
teste_https
restic_lab snapshots
```

3. Confere a checklist T0–T17: tarefa realizada, evidência observada, explicação e eventual apoio/reposição. Não marques uma tarefa como demonstrada pelo formando quando foi apenas reposta pelo formador.
4. Recolhe a folha e as capturas pelo meio acordado, sem segredos. Entrega o roteiro de estudo e recolhe a satisfação.
5. Faz a limpeza de credenciais, CA e PSK segundo o plano do laboratório depois de terminarem os usos autorizados. Não destruas o único acesso a um backup que ainda deva ser conservado.

## Reposições e gestão da sessão

| Hora | Base a repor | Condição de saída |
|---|---|---|
| 08:45 | CP4 funcional, com origem identificada | HTTP esperado e volume identificado |
| 10:35 | Site HTTP de referência | Nome e marcador corretos |
| 11:15 | Certificado e configuração HTTPS de referência | Nome/CA/conteúdo validados |
| 11:45 | Reversão das falhas de T6 | Serviço saudável para o backup |
| 14:00 | Repositório de treino com snapshot e custódia disponíveis | Consulta e restauro seletivo possíveis |
| 15:00 | Serviço funcional após T11 | Continuidade para monitorização |
| 15:50 | Host/cenário de reserva preparado | Recolha recente e trigger aplicável |

Se os scripts privados do laboratório estiverem disponíveis, o formador pode executar na **sua máquina / Proxmox**, com os parâmetros certos:

```bash
bash "$LAB_FORMADOR/formador.sh" remoto "$POSTO" verificar
```

Os pontos suportados pelo script privado são `repor cp4`, `repor http`, `repor https`, `repor t6`, `repor backup` e `repor servico`. Não executes a lista inteira: escolhe apenas a reposição necessária, regista-a e volta a validar o resultado. Para o host de reserva, usa o frontend ou o procedimento preparado na VM Zabbix.

Um repositório de referência só é adequado a T11 se contiver o caminho e a versão de ficheiro que vais pedir para recuperar. Confirma com `restic ls`; não concluas que um repositório está pronto apenas porque contém algum snapshot.

Se houver atraso, encurta por esta ordem: extensão proxy/502 de T6; segunda falha de T6; segunda simulação de T9; trigger adicional do limiar de T13. Conserva HTTPS, backup, restauro, ciclo PROBLEM/RESOLVED e incidente integrado. Regista o que não foi realizado na checklist e remete para estudo autónomo.

## Checklist rápida do formador

- [ ] CP4 pronta em cada posto, com volume e origem confirmados.
- [ ] Parâmetros, CA e acessos de recuperação conferidos.
- [ ] Conteúdo, Nginx, permissões e HTTPS verificados.
- [ ] Snapshot Restic identificável, segredo em custódia e restauro demonstrado.
- [ ] Timer distinguido da execução efetiva do backup.
- [ ] Agentes, cenário, triggers e recuperação observados com dados recentes.
- [ ] T6 e T16 ensaiados com reversão antes de os aplicar aos formandos.
- [ ] Evidências de monitorização e logs correlacionadas, com instantes/fusos.
- [ ] Apoios e reposições registados sem inventar competências demonstradas.
- [ ] Timers de treino desativados e materiais entregues.
