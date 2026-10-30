# Preparar a aplicação CP4 numa VM nova

**Guia de apoio ao formando — ponto de partida para T0**

Neste exercício, **CP4** é o nome da aplicação HTTP usada nas tarefas seguintes. A aplicação é composta por um serviço Python iniciado com Docker Compose e por um volume nomeado que guarda os ficheiros publicados.

O objetivo é obter uma aplicação que responda por HTTP e cujos dados continuem disponíveis depois de substituir o contentor. O Compose descreve como executar o serviço; o volume guarda os dados da aplicação.

Executa os comandos **dentro da tua VM Ubuntu**, numa sessão SSH, com o utilizador atribuído pelo formador. O Docker, o plugin Compose e o curl devem estar instalados na preparação do laboratório. A criação da CP4 é uma preparação para T0; os restantes exercícios começam com esta base funcional.

Os nomes, a porta e os caminhos dentro do contentor apresentados abaixo constituem um **modelo didático**. Confirma com o formador que correspondem à tua ficha antes de o executar. Não são publicados endereços da rede nem credenciais dos postos.

## 1. Verificar o ponto de partida

```bash
hostname
sudo systemctl is-active docker
sudo docker compose version
sudo docker ps -a --filter label=com.docker.compose.project=cp4
sudo docker volume ls
sudo ss -ltnp 'sport = :8000'
```

- **Se já existir uma CP4 funcional fornecida pelo formador:** identifica o contentor e o volume e confirma o HTTP. Regista a origem como «referência fornecida» e segue para T0. Não precisas de criar outra aplicação.
- **Se a CP4 estiver em falta:** segue as secções 2–5 para a criar de raiz.
- **Se existir mas estiver parada ou avariada:** consulta a secção 6 e usa o ficheiro Compose da aplicação existente.
- Se a porta estiver ocupada por outro serviço ou se o Docker/Compose estiver em falta, resolve esse pré-requisito com o formador antes de continuar.

## 2. Criar o ficheiro Compose

Cria uma pasta de trabalho na tua conta. O bloco seguinte recusa substituir um ficheiro `compose.yaml` já existente.

```bash
(
    set -e
    mkdir -p "$HOME/cp4"
    cd "$HOME/cp4"

    if [ -e compose.yaml ]; then
        echo "Já existe compose.yaml: conserva-o e verifica-o antes de continuar."
        exit 1
    fi

    cat > compose.yaml <<'YAML'
name: cp4
services:
  app:
    image: python:3.13-slim
    command: ["python", "-m", "http.server", "8000", "--directory", "/dados"]
    ports:
      - "127.0.0.1:8000:8000"
    volumes:
      - dados:/dados
    restart: unless-stopped
volumes:
  dados:
    name: cp4_dados
YAML
)
```

Neste modelo:

| Elemento | Função |
|---|---|
| Projeto `cp4` | Identifica o conjunto gerido por Compose |
| Serviço `app` | Executa o servidor HTTP didático |
| `python:3.13-slim` | Imagem usada pelo serviço |
| `127.0.0.1:8000:8000` | Publica a porta HTTP apenas na própria VM |
| Volume `cp4_dados` | Guarda os dados de forma persistente |
| Montagem `/dados` | Torna os ficheiros do volume acessíveis no contentor |

A propriedade `name` fixa o nome do volume. O Compose cria-o se estiver em falta e reutiliza-o quando já existe. [Documentação Docker sobre volumes](https://docs.docker.com/reference/compose-file/volumes/)

## 3. Validar e iniciar

```bash
cd "$HOME/cp4"
sudo docker compose config --quiet
```

Se a validação terminar sem erro, inicia a aplicação:

```bash
sudo docker compose up -d
sudo docker compose ps
```

O primeiro arranque pode precisar de descarregar a imagem. O serviço `app` deve ficar em execução. Se houver erro, lê a mensagem e resolve-o antes de avançar.

## 4. Criar os dados iniciais e testar o HTTP

Cria uma página e um ficheiro de dados **dentro do volume**. Este bloco mantém os ficheiros se já existirem.

```bash
cd "$HOME/cp4"
sudo docker compose exec -T app sh -c '
    if [ ! -e /dados/index.html ]; then
        printf "%s\n" "<h1>CP4 - aplicacao do laboratorio</h1>" > /dados/index.html
    fi
    if [ ! -e /dados/dados.txt ]; then
        printf "%s\n" "CP4-DADOS-OK" > /dados/dados.txt
    fi
'
```

Confirma o resultado a partir da própria VM:

```bash
curl --retry 10 --retry-connrefused --retry-delay 1 --max-time 10 \
    --fail --silent --show-error http://127.0.0.1:8000/

curl --retry 10 --retry-connrefused --retry-delay 1 --max-time 10 \
    --fail --silent --show-error http://127.0.0.1:8000/dados.txt

curl --silent --output /dev/null --write-out '%{http_code}\n' \
    http://127.0.0.1:8000/
```

**Resultado esperado numa criação nova:** a página contém `CP4`, o ficheiro contém `CP4-DADOS-OK` e o último comando apresenta `200`.

O endereço `127.0.0.1` refere-se à máquina onde executas o curl. Para estes testes, utiliza a shell da VM. O Nginx será trabalhado nas tarefas seguintes.

Identifica também a montagem e a localização efetiva do volume:

```bash
sudo docker inspect "$(sudo docker compose ps -q app)" \
    --format '{{range .Mounts}}{{println .Name "->" .Destination}}{{end}}'

sudo docker volume inspect cp4_dados --format '{{.Mountpoint}}'
```

Regista o nome do volume e confirma o caminho com o formador. Será usado no backup de T7 e no modelo do timer de T10. Não alteres esse caminho durante os exercícios.

## 5. Demonstrar a persistência

Nesta verificação vais substituir o contentor e manter o volume.

```bash
cd "$HOME/cp4"

sudo docker compose exec -T app sh -c \
    'printf "%s\n" "PERSISTENCIA-CP4" > /dados/teste-persistencia.txt'

ANTES=$(sudo docker compose ps -q app)
sudo docker compose up -d --force-recreate app
DEPOIS=$(sudo docker compose ps -q app)

printf 'Contentor antes:  %s\nContentor depois: %s\n' "$ANTES" "$DEPOIS"

curl --retry 10 --retry-connrefused --retry-delay 1 --max-time 10 \
    --fail --silent --show-error http://127.0.0.1:8000/teste-persistencia.txt
```

**Critério de sucesso:** os IDs dos contentores são diferentes e o pedido continua a devolver `PERSISTENCIA-CP4`. O `--force-recreate` substitui o contentor; os volumes montados são preservados. [Documentação Docker sobre recriação](https://docs.docker.com/reference/cli/docker/compose/up/)

Responde na folha de evidências:

1. O que foi substituído e o que permaneceu?
2. Onde estão os dados servidos pela aplicação?
3. Porque é que esta persistência ainda não substitui um backup?

## 6. O que fazer ou refazer se falhar

Para a aplicação criada por este guia, trabalha na pasta que contém o seu `compose.yaml`:

```bash
cd "$HOME/cp4"
sudo docker compose ps -a
sudo docker compose logs --tail 50 app
sudo docker compose config --quiet
```

| Situação | Ação |
|---|---|
| O ficheiro Compose existe e a aplicação está parada | Valida a configuração e executa `sudo docker compose up -d`; repete o teste HTTP |
| A configuração está correta, mas é necessário substituir o contentor | Executa `sudo docker compose up -d --force-recreate app`; verifica novamente o conteúdo e o volume |
| A porta já está ocupada | Identifica o serviço com o formador; confirma o projeto correto antes de alterar portas ou parar serviços |
| O HTTP responde, mas o ficheiro esperado não aparece | Confirma o ficheiro dentro do volume e a montagem efetiva antes de corrigir |
| O volume está em falta ou perdeu dados anteriores | A criação de um volume vazio não recupera esses dados; pede apoio e usa um backup ou uma referência identificada |
| A CP4 foi fornecida pelo formador noutro local | Usa a configuração original indicada na ficha; regista a reposição recebida |

Ao refazer a aplicação, **mantém o volume**. Não uses `docker compose down -v`, remoção de volumes ou limpeza global para resolver este exercício.

## 7. Entrega da preparação

Regista em T0 da [folha de respostas](FOLHA_DE_RESPOSTAS.md):

- Origem da CP4: criada por ti, retomada ou fornecida pelo formador.
- Pasta do Compose, projeto, serviço e contentor.
- Nome do volume, destino no contentor e caminho confirmado para o backup.
- Código e conteúdo HTTP observados.
- Prova de persistência, quando realizada: IDs antes/depois e conteúdo preservado.
- Apoios ou reposições recebidos.

Com esta base funcional, continua no [enunciado da sessão final](README.md).
