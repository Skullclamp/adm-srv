# Material do formador

Esta pasta reúne a resolução da sessão prática M4–M8, incluindo a preparação da aplicação CP4 em VMs novas.

**O repositório é público: esta pasta também pode ser consultada pelos formandos.** A designação `formador` organiza o material; não restringe o acesso às soluções.

## Conteúdo

| Ficheiro | Utilização |
|---|---|
| [GUIA_RESOLUCAO.md](GUIA_RESOLUCAO.md) | Resolução passo a passo de T0–T17, resultados esperados, respostas, falhas e recuperação |
| [parametros.exemplo.sh](parametros.exemplo.sh) | Modelo sem valores da infraestrutura, para preencher numa cópia local |
| [docker-lab/](docker-lab/) | Stack Docker do formador: CP4, Nginx/HTTPS, Restic, Zabbix e falhas reversíveis |
| [.gitignore](.gitignore) | Evita adicionar por engano parâmetros privados, chaves e evidências nesta pasta |

## Como utilizar

Para montar uma demonstração Docker automaticamente, segue o [guia da stack do formador](docker-lab/README.md). Esta opção é independente das VMs nativas e adapta o agendamento e os logs ao contexto dos contentores.

1. Lê o [enunciado dos formandos](../README.md), a [preparação CP4](../PREPARAR_CP4.md) e a [folha de respostas](../FOLHA_DE_RESPOSTAS.md).
2. Copia `parametros.exemplo.sh` para `~/parametros-posto.sh` na máquina onde vais executar os comandos. Preenche os valores da ficha privada do posto.
3. Em cada nova shell, carrega a cópia revista com `source "$HOME/parametros-posto.sh"`. Na VM do posto, executa também `validar_parametros`.
4. Segue uma tarefa de cada vez e confirma o resultado antes da seguinte. Os blocos não constituem um instalador para executar integralmente.
5. Nas secções de falhas, introduz apenas uma falha de cada vez e conserva uma via de recuperação por consola.

Não coloques no repositório os valores das PSK, palavras-passe, chaves privadas, ficheiros de parâmetros preenchidos ou evidências com dados do laboratório. Os exemplos usam variáveis para os parâmetros de execução.

## Onde executar

| Indicação no guia | Máquina / interface |
|---|---|
| VM do posto | Shell Ubuntu do posto atribuído, normalmente como utilizador comum com `sudo` |
| Máquina do formador / Proxmox | Shell com acesso à CA existente e aos scripts privados do laboratório |
| VM Zabbix | Shell do servidor Zabbix, com os privilégios indicados |
| Browser do Windows | Frontend Zabbix e navegação web |

Os comandos `docker`, `nginx`, `restic`, `systemctl` e os caminhos Linux apresentados nas tarefas destinam-se ao contexto Linux indicado. O PowerShell do Windows pode ser usado para abrir as sessões SSH.

## Validação e limites

Este guia adapta a documentação da sessão e os materiais correntes do repositório. A verificação desta publicação é estática: sintaxe dos blocos Bash, ligações e cobertura das tarefas. Não equivale a um ensaio destes procedimentos nas VMs da sala.

Os tempos e a ordem seguem o enunciado: sessão de 8 horas, T0–T17 e avaliação formativa. A criação da CP4 é uma preparação para o arranque; se consumir o tempo de T0, aplica uma referência funcional e regista o apoio recebido. A configuração de plataformas, pacotes e hipervisor pertence à preparação técnica do laboratório.
