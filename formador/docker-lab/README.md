# Laboratório Docker do formador

O comando `subir` prepara uma demonstração funcional de CP4, Nginx, HTTPS, backups Restic e monitorização Zabbix. Cria os dados iniciais, certificados, segredos, host com PSK, cenário web, triggers e primeiro backup. Os arranques seguintes conservam os dados existentes.

Executar **numa VM Ubuntu com Docker Engine e Docker Compose v2**. O PowerShell do Windows serve para abrir a ligação SSH e o túnel para o browser. Esta stack não cria VMs no Proxmox.

Para criar também a VM e instalar os pré-requisitos automaticamente, usa o [script para o Proxmox](../proxmox/README.md), que prepara uma VM Ubuntu 26.04 LTS e arranca esta stack.

## 1. Arrancar na VM Ubuntu

Pré-requisitos: `docker`, `docker compose`, `openssl`, `flock` e `git`. Se faltar Docker, segue a [instalação oficial para Ubuntu](https://docs.docker.com/engine/install/ubuntu/); o script verifica as dependências antes de preparar o laboratório.

No terminal **da VM Ubuntu**:

```bash
git clone https://github.com/Skullclamp/adm-srv.git
cd adm-srv/formador/docker-lab
sudo bash lab-formador.sh subir
sudo bash lab-formador.sh acessos
```

Se já tens este repositório clonado, atualiza essa cópia com `git pull --ff-only` e entra na pasta `formador/docker-lab`.

O primeiro arranque descarrega as imagens e inicializa a base de dados do Zabbix. O script aguarda pela API e por amostras recentes do agente e do cenário HTTPS. Se terminar com erro, lê a mensagem, consulta `logs` e repete `subir` depois de corrigir a causa. Conserva `.runtime` e os volumes.

O utilizador do frontend Zabbix é **Admin**. A palavra-passe é gerada localmente e apresentada por `acessos`. As contas dos contentores não são contas Ubuntu; o acesso SSH usa a conta já existente na VM.

## 2. Aceder pelo Windows

Os três serviços publicados escutam em `127.0.0.1` da VM. Abre uma segunda janela de **PowerShell no Windows**, substitui `IP_DA_VM_DOCKER` e mantém a ligação aberta:

```powershell
ssh -N -o ExitOnForwardFailure=yes -L 8080:127.0.0.1:8080 -L 8443:127.0.0.1:8443 -L 8081:127.0.0.1:8081 ubuntu@IP_DA_VM_DOCKER
```

| Serviço | Endereço no browser do Windows |
|---|---|
| Site Nginx — T3 | <http://localhost:8080> — redireciona para HTTPS |
| Site com TLS — T5 | <https://localhost:8443> |
| Ficheiro monitorizado | <https://localhost:8443/estado.html> |
| Aplicação CP4 por reverse proxy | <https://localhost:8443/app/> |
| Dados persistentes de CP4 | <https://localhost:8443/app/dados.txt> |
| Zabbix | <http://localhost:8081> |

O certificado é emitido por uma CA privada de laboratório. Para exportar **apenas o certificado público** para o Windows, noutra janela PowerShell, ajusta o caminho caso tenhas clonado o repositório noutra pasta:

```powershell
ssh ubuntu@IP_DA_VM_DOCKER "cd ~/adm-srv/formador/docker-lab && sudo bash lab-formador.sh ca" |
    Out-File -Encoding ascii "$HOME\Downloads\ca-formador.crt"
```

Para o browser confiar neste laboratório, importa `ca-formador.crt` para as autoridades de certificação de raiz de confiança do **utilizador atual**, depois de confirmares que corresponde à CA que acabaste de gerar. Firefox pode usar um repositório próprio de autoridades. O Zabbix e as verificações internas recebem esta CA automaticamente e verificam também o nome do certificado.

## 3. O que fica montado

| Serviço / volume | Função |
|---|---|
| `cp4` / `cp4_dados` | Imagem Python com HTTP na porta interna 8000 e dados persistentes |
| `web` / `site` | Nginx com site, redirecionamento HTTP, HTTPS e proxy `/app/` para CP4 |
| `db` / `base_zabbix` | PostgreSQL e configuração/histórico do Zabbix |
| `zabbix-db-init` | Inicialização da base; é normal ficar terminado com código 0 |
| `zabbix-server`, `zabbix-web` | Zabbix 7.0 e frontend |
| `agent` | Agent 2 passivo com TLS-PSK; a porta 10050 fica na rede Docker |
| `restic` / `repositorio` | Ferramenta de backup e repositório cifrado |
| `agendador` | Backup automático a cada 1800 segundos, após o primeiro backup |
| `ferramentas` / `estado`, `restauros` | Configuração, registo da falha ativa e restauro em staging |

Os serviços `restic` e `ferramentas` são temporários: executam uma operação e terminam. O projeto chama-se `adm-srv-formador` e usa volumes e rede próprios.

Em `.runtime/` ficam os parâmetros privados, palavra-passe do Restic, CA, chave da CA, certificado/chave do site e configuração Nginx. Esta pasta está no `.gitignore`. Os backups incluem site, configuração Nginx, dados CP4 e material TLS do site; **não incluem a base Zabbix nem a custódia completa de `.runtime`**. Guarda uma cópia privada de `.runtime`, além dos dados/volumes necessários à recuperação da VM. Sem o segredo Restic não consegues decifrar o repositório.

O certificado do site dura 30 dias e a CA 365. Uma emissão expirada exige renovação com a CA existente; o script interrompe o arranque em vez de substituir as chaves. As imagens usam as versões principais indicadas em `compose.yaml`; as tags podem receber atualizações. Regista as imagens efetivamente usadas com `versoes`.

## 4. Verificar e observar

Todos os comandos seguintes são para a **VM Ubuntu**, dentro desta pasta:

```bash
sudo bash lab-formador.sh estado
sudo bash lab-formador.sh verificar
sudo bash lab-formador.sh logs web
sudo bash lab-formador.sh logs agendador
sudo bash lab-formador.sh versoes
```

`verificar` confirma TLS com CA e nome válidos, conteúdo do site, CP4 através do proxy, `agent.ping=1`, cenário web recente com resultado 0 e integridade estrutural do repositório Restic. A verificação de integridade não substitui o exercício de restauro.

No Zabbix, abre o host **docker-formador**, no grupo **Formacao/Docker**. O template é **Linux by Zabbix agent**. O cenário **HTTPS-formador** verifica, a cada 15 segundos, `/estado.html` e `/app/dados.txt`, exigindo HTTP 200 e o conteúdo esperado. O trigger do site passa a PROBLEM quando uma etapa falha e a RESOLVED quando volta a funcionar. Consulta também os valores recentes dos itens.

O segundo trigger usa CPU acima de 80% durante cinco minutos. Para observar a variação do item com carga curta:

```bash
sudo bash lab-formador.sh carga 30
```

A carga usa até dois processos e termina automaticamente; aceita 1–120 segundos. Esta demonstração curta não garante o disparo do trigger de cinco minutos. As métricas seguem o contexto que o agente consegue observar num contentor Linux, com kernel partilhado.

## 5. Backups e restauro seletivo

Cria um backup funcional e anota o respetivo ID **antes** de introduzir a falha:

```bash
sudo bash lab-formador.sh backup
sudo bash lab-formador.sh snapshots
sudo bash lab-formador.sh retencao
```

`retencao` executa apenas uma simulação: mantém os últimos 3 snapshots, 7 diários e 4 semanais. Todos os backups usam o hostname Restic `formador-docker`, para agrupar a retenção de forma consistente entre contentores temporários.

Para demonstrar a perda de `estado.html` e a recuperação a partir de um snapshot, substitui `ID_DO_SNAPSHOT` pelo ID anotado:

```bash
sudo bash lab-formador.sh falha t16-c
sudo bash lab-formador.sh logs web
sudo bash lab-formador.sh restaurar ID_DO_SNAPSHOT estado.html
sudo bash lab-formador.sh verificar
```

O restauro entra primeiro num diretório próprio de staging e promove apenas o ficheiro escolhido. Aceita `estado.html` e `teste-restauro.html`; não substitui a árvore inteira do site. O ID é opcional, com `latest` por omissão, mas um backup tirado durante a falha pode já não conter o ficheiro. Nesse caso, usa um snapshot anterior. Um ficheiro ausente no staging impede a promoção.

## 6. Falhas para demonstração

Introduz **uma falha de cada vez**. O script regista a referência necessária para a reposição e recusa sobrepor falhas.

| ID | Alteração | Resultado esperado |
|---|---|---|
| `t6-1` | `estado.html` passa a modo 600 | HTTP 403 |
| `t6-404` | Raiz Nginx aponta para uma pasta inexistente | HTTP 404 |
| `t6-502` | Para CP4 | HTTP 502 em `/app/` |
| `t14` | Para o Nginx | Indisponibilidade HTTPS |
| `t16-a` | Diretório do site passa a modo 700 | HTTP 403 |
| `t16-b` | Introduz uma diretiva Nginx inválida e reinicia | Falha de arranque do Nginx, visível nos logs |
| `t16-c` | Remove `estado.html` | HTTP 404 |

Exemplo de falha, diagnóstico e reposição:

```bash
sudo bash lab-formador.sh falha t6-502
sudo bash lab-formador.sh logs web
sudo bash lab-formador.sh repor t6-502
sudo bash lab-formador.sh verificar
```

Entre `falha` e `repor`, consulta o Zabbix e aguarda pelo PROBLEM; depois da reposição, aguarda pelo RESOLVED. O estado Docker `healthy` do Nginx verifica apenas `/healthz` e pode continuar saudável numa falha do conteúdo; o cenário Zabbix verifica o serviço publicado.

`repor` recupera a referência guardada na introdução da falha. Para avaliar a recuperação por backup em T16-C, usa `restaurar` como no ponto 5. O agendador continua ativo durante os exercícios e pode guardar também estados com falhas; escolhe os snapshots pela data e conteúdo.

## 7. Parar e retomar

```bash
sudo bash lab-formador.sh parar
sudo bash lab-formador.sh subir
```

`parar` conserva os volumes, backups e `.runtime`. Se existir uma falha ativa, usa `repor` antes de tentar novamente `subir`; `repor` também permite voltar a iniciar os serviços necessários. Não apagues `.runtime` para recomeçar: essa pasta contém as chaves dos dados já criados.

As portas e o intervalo de backup podem ser alterados em `.runtime/lab.env`, depois de `preparar`. As portas devem ser diferentes e os serviços continuam em loopback. Se alterares `HTTPS_PORT`, ajusta também a porta de redirecionamento em `.runtime/nginx/default.conf` e o túnel SSH. Aplica a configuração com `subir`. Conserva os segredos existentes.

## 8. Relação com o enunciado e limites

Esta stack serve para demonstração do formador. Inclui a CP4 que falta nas VMs novas e o site Nginx de T3. Mantém os conceitos de TLS, PSK, backup, retenção, restauro e diagnóstico, com estas adaptações:

- O agendamento é feito por um contentor, em vez de um timer systemd de T10.
- Os logs são consultados com Compose, em vez de `journalctl` dos serviços nativos.
- SSH, UFW, contas Ubuntu e administração de VMs continuam a ser exercícios no sistema anfitrião/VM; não são simulados dentro dos contentores.
- O Zabbix desta demonstração é independente do servidor já preparado para os formandos. O cenário usa 15 segundos para facilitar a observação.

Para a resolução no ambiente original, usa o [guia do formador](../GUIA_RESOLUCAO.md).

Foram verificadas a sintaxe dos scripts, a estrutura Compose contra o schema oficial e as operações locais de conservação de dados, falhas e restauro por testes Python. **Esta publicação ainda precisa de um ensaio de integração numa máquina com Docker**: o ambiente onde foi preparada não dispõe de Docker. O comando `subir` executa as verificações de integração ao montar a stack.

Para executar os testes locais sem Docker, nesta pasta:

```bash
python3 -m unittest discover -s tests -v
```

Referências: [contentores Zabbix 7.0](https://www.zabbix.com/documentation/7.0/en/manual/installation/containers), [ordem de arranque no Compose](https://docs.docker.com/compose/how-tos/startup-order/) e [Restic](https://restic.readthedocs.io/en/v0.18.1/).
