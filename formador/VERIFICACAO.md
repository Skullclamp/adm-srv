# Verificação do material — 30-10-2026

Foi revisto o percurso comum do formador e dos formandos: preparação CP4, tarefas T0–T17, parâmetros, instalação nativa e criação/adaptação da VM no Proxmox. Bash, YAML, Nginx, HTML e conteúdo de unidades systemd continuam em blocos separados nos guias.

| Área | Correção ou verificação |
|---|---|
| CP4 e T0 | Pasta `~/cp4`, projeto `cp4`, serviço `app` e volume `cp4_dados`; recusa de inspeção sem contentor identificado |
| Parâmetros | Campos obrigatórios, IPv4, rede, URL, caminhos absolutos normalizados e portas válidas e distintas; carregamento e validação nos blocos que usam os parâmetros |
| T1–T2 | Amostra existente antes da cópia; hashes e arquivo verificados; ferramentas e aplicação confirmadas antes da carga limitada por tempo |
| T3 | Nginx instalado no Ubuntu, conteúdo e configuração de trabalho existentes, marcadores preenchidos e reversão se `nginx -t` recusar a configuração |
| T4 | Workers identificados pelos filhos do `MainPID` do serviço Nginx; caminhos conferidos antes das permissões; firewall para na primeira regra recusada e mantém SSH |
| T5 | CSR com parâmetros validados; assinatura no Proxmox com a CA existente; extensão SAN preenchida; certificado, nome, finalidade e chave verificados antes da instalação |
| T6 | Falhas delimitadas, cópia da configuração e validação antes de recarregar; serviço Compose `app` na extensão proxy |
| T7–T9 | Disco de backup montado, volume correto, segredo existente conservado e retenção apenas com `--dry-run` |
| T10 | Modelos preenchidos, calendário e unidades validados antes da instalação; primeira execução de backup antes de ativar o timer |
| T11 | Snapshot escolhido e hash conferido antes da perda; ficheiro retido para recuperação; staging novo e hash conferido antes de promover |
| T12–T13 | Contextos posto/servidor Zabbix/Proxmox explícitos; teste PSK com ficheiro privado presente; distribuição apenas da CA pública e verificação no servidor que executa o cenário |
| T14–T15 | Paragem/arranque controlados e consulta dos logs e parâmetros do posto |
| T16 | Uma falha de cada vez; cópias para reversão; cenário de perda condicionado ao snapshot e promoção condicionada ao hash |
| T17 | Desativação do timer e distinção entre os estados esperados `disabled`/`inactive` e uma falha de execução |
| Migração CP4 | Cópia inicial verificada, conflitos conservados e marcador de identidade; repetições não substituem o trabalho feito depois da migração |
| Proxmox | Identidade da VM pela API JSON; bloqueio supervisionado com `flock --close`; recuperação do bloqueio antigo apenas se os titulares forem QEMU |

## Validação executada

- **53 testes:** 52 passaram e um teste de permissões POSIX foi omitido por o ambiente de validação ser Windows.
- Sintaxe de **136 blocos Bash** da documentação e **seis scripts Bash**, incluindo o bootstrap gerado para a VM.
- Compilação dos ficheiros Python e validação dos **dois modelos Compose** segundo o esquema oficial do Compose.
- Ligações relativas entre os documentos e igualdade entre o YAML CP4 do guia e o ficheiro instalado.
- Execução em Bash dos casos de parâmetros em falta/inválidos, seleção dos workers nativos e recusa de ativar a firewall depois de uma regra falhar.
- Migração com dados binários, subpastas, conflito, repetição depois de alterações na aula e mudança da identidade do volume.
- APIs Proxmox simuladas, geração cloud-init e arranque completo pelos dois supervisores de bloqueio; o teste reproduz também a regressão de reentrada da versão anterior.
- Testes de conservação/restauro da stack Docker anterior, mantida para recuperação.
- Dez testes da preparação direta na VM: despacho do bloqueio, endereços SSH, exportação apenas de configuração pública, recusa de chaves privadas, seleção do disco, uso do ponto de montagem existente e reutilização de Docker/Compose. SSH, discos e serviços são simulados; não foi efetuada uma ligação à infraestrutura.
- Guia Zabbix da CP4: cinco testes da documentação passaram; comandos de criação, simulação de conteúdo errado e recuperação executados em ficheiros temporários, incluindo a recusa de substituir dados preexistentes ou uma cópia de outro posto. Os itens, triggers e eventos são confirmados no frontend durante a execução do guia.

Os testes estão em `tests/`, `formador/proxmox/tests/` e `formador/docker-lab/tests/`. Os testes Bash usam a variável opcional `BASH_FOR_TESTS` quando o executável não se chama `bash` no sistema de validação.

## O que exige confirmação nas VMs

Não foi executada uma criação ou migração real de VM, nem um ensaio completo de Nginx, TLS, UFW, Restic, systemd e Zabbix na infraestrutura da sala. Os resultados esperados do guia são critérios a observar durante essa execução. A exclusão pelo kernel dos bloqueios `flock` e as permissões POSIX devem ser confirmadas em Linux; os testes locais verificam a chamada dos supervisores e a lógica de identificação dos titulares.

Na VM Ubuntu, `sudo bash "$HOME/adm-srv/preparar-posto.sh" verificar` confirma os pré-requisitos locais. No Proxmox, `bash criar-vm-formador.sh diagnostico` mostra o estado e os logs da preparação. HTTPS, backup/restauro e recolha central de métricas são confirmados nas tarefas correspondentes.
