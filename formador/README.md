# Material do formador

Esta pasta reúne a resolução da sessão prática M4–M8, incluindo a preparação da aplicação CP4 em VMs novas.

**O repositório é público: esta pasta também pode ser consultada pelos formandos.** A designação `formador` organiza o material; não restringe o acesso às soluções.

## Conteúdo

| Ficheiro | Utilização |
|---|---|
| [GUIA_RESOLUCAO.md](GUIA_RESOLUCAO.md) | Resolução passo a passo de T0–T17, resultados esperados, respostas, falhas e recuperação |
| [parametros.exemplo.sh](parametros.exemplo.sh) | Modelo sem valores da infraestrutura, para preencher numa cópia local |
| [VERIFICACAO.md](VERIFICACAO.md) | Correções de T0–T17, testes executados e limites da validação |
| [Ambiente comum](../AMBIENTE_COMUM.md) | Mesmos nomes, pastas e comandos para formador e formandos |
| [Preparar posto](../preparar-posto.sh) | Preparação comum de CP4, Nginx, Restic, Agent 2, parâmetros e modelos |
| [proxmox/](proxmox/) | Criar ou alinhar a VM Ubuntu 26.04 com o ambiente dos formandos |
| [preparar-vm-direto.sh](preparar-vm-direto.sh) | Preparar a VM Ubuntu diretamente por SSH, sem depender do agente QEMU |
| [docker-lab/](docker-lab/) | Stack anterior, conservada para recuperação dos dados existentes |
| [.gitignore](.gitignore) | Evita adicionar por engano parâmetros privados, chaves e evidências nesta pasta |

## Como utilizar

O posto do formador segue o [mesmo ambiente dos formandos](../AMBIENTE_COMUM.md). Usa a mesma CP4 em `~/cp4`, com serviço `app` e volume `cp4_dados`, e os serviços Nginx, Restic, Agent 2 e systemd no Ubuntu.

Usa o [script do Proxmox](proxmox/README.md) para criar a VM ou `alinhar` para adaptar a VM antiga. O script prepara o estado inicial; segue depois T0–T17 para demonstrar a mesma resolução dos formandos.

1. Lê o [enunciado dos formandos](../README.md), a [preparação CP4](../PREPARAR_CP4.md) e a [folha de respostas](../FOLHA_DE_RESPOSTAS.md).
2. A preparação comum gera `~/parametros-posto.sh`. Num posto preparado manualmente, copia `parametros.exemplo.sh` para esse caminho e preenche os valores da ficha privada.
3. Em cada nova shell, carrega a cópia revista com `source "$HOME/parametros-posto.sh"`. Na VM do posto, executa também `validar_parametros`.
4. Segue uma tarefa de cada vez e confirma o resultado antes da seguinte. Os blocos não constituem um instalador para executar integralmente.
5. Nas secções de falhas, introduz apenas uma falha de cada vez e conserva uma via de recuperação por consola.

Não coloques no repositório os valores das PSK, palavras-passe, chaves privadas, ficheiros de parâmetros preenchidos ou evidências com dados do laboratório. Os exemplos usam variáveis para os parâmetros de execução.

## Onde executar

### Preparar diretamente a VM do formador

Na sessão PuTTY em que aparece **`ubuntu@formador-docker`**, descarrega e executa:

```bash
cd "$HOME"
curl -fL --retry 3 \
  https://raw.githubusercontent.com/Skullclamp/adm-srv/main/formador/preparar-vm-direto.sh \
  -o preparar-vm-direto.sh &&
sudo bash preparar-vm-direto.sh
```

O script pede o IP ou nome do Proxmox, o mesmo endereço usado no PuTTY, e abre uma ligação SSH como `root`. A autenticação é a normal do SSH; a palavra-passe não é guardada pelo script. No Proxmox, lê apenas o IP do Zabbix em `/root/laboratorio/lab.conf` e o certificado público em `/root/laboratorio/segredos/ca-lab.crt`.

Reutiliza Docker e Compose quando já funcionam, instala os restantes pré-requisitos, atualiza o material e executa a preparação comum. O disco de backup deve estar montado em `/srv/backup` ou ter o serial `lab-backup-NUMERO`; só inicializa um disco vazio com o serial identificado. Conserva os volumes antigos e o trabalho da CP4. Mantém o PuTTY aberto até aparecer **Preparação concluída**.

Depois, na mesma shell Ubuntu:

```bash
source "$HOME/parametros-posto.sh" &&
validar_parametros
```

Os parâmetros ficam gerados em `/home/ubuntu/parametros-posto.sh`. Segue depois T0–T17; o script prepara a base dos exercícios. O progresso e os erros ficam em `/var/log/adm-srv-formador.log`. O agente QEMU não é usado nesta execução.

As opções estão em `sudo bash preparar-vm-direto.sh --help`. Com `--ip-zabbix IP --ca-cert FICHEIRO`, usa os parâmetros já distribuídos e dispensa a ligação ao Proxmox. Nos postos dos formandos que já têm Docker e Compose, o [preparar-posto.sh](../preparar-posto.sh) continua disponível para a preparação comum.

### Contextos dos exercícios

| Indicação no guia | Máquina / interface |
|---|---|
| VM do posto | Shell Ubuntu do posto atribuído, normalmente como utilizador comum com `sudo` |
| Máquina do formador / Proxmox | Shell com acesso à CA existente e aos scripts privados do laboratório |
| VM Zabbix | Shell do servidor Zabbix, com os privilégios indicados |
| Browser do Windows | Frontend Zabbix e navegação web |

Os comandos `docker`, `nginx`, `restic`, `systemctl` e os caminhos Linux apresentados nas tarefas destinam-se ao contexto Linux indicado. O PowerShell do Windows pode ser usado para abrir as sessões SSH.

## Validação e limites

Este guia adapta a documentação da sessão e os materiais correntes do repositório. A [verificação desta publicação](VERIFICACAO.md) inclui sintaxe dos blocos Bash, ligações, parâmetros e testes de migração e de serviços simulados. Não equivale a um ensaio destes procedimentos nas VMs da sala.

Os tempos e a ordem seguem o enunciado: sessão de 8 horas, T0–T17 e avaliação formativa. A criação da CP4 é uma preparação para o arranque; se consumir o tempo de T0, aplica uma referência funcional e regista o apoio recebido. A configuração de plataformas, pacotes e hipervisor pertence à preparação técnica do laboratório.
