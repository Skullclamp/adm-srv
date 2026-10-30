# Folha de respostas e evidências — Sessão final M4–M8

Consulta o [enunciado do exercício](README.md) e preenche esta folha durante a execução.

**Nome:** ____________________  
**Posto / hostname / IP:** ____________________  
**Data e fuso horário:** ____________________

Regista comandos ou consultas utilizados, resultados relevantes e explicações. Identifica qualquer apoio ou reposição do formador. Não incluas palavras-passe, chaves privadas, valores de PSK ou capturas que os revelem. Entrega pelo meio indicado pelo formador.

## T0 — Ponto de partida

| Campo | Resposta / evidência |
|---|---|
| Hostname, utilizador e versão do sistema | |
| Tempo desde o arranque | |
| Origem da CP4: criada nesta VM / retomada / referência fornecida | |
| Pasta Compose / projeto / serviço / contentor CP4 | |
| Volume persistente / destino no contentor / caminho confirmado para backup | |
| Endpoint, código HTTP, conteúdo e hora do teste | |
| Prova de persistência: IDs antes/depois e conteúdo preservado, se realizada | |
| Apoio ou reposição recebida | |

## T1 — Proteção e restauro amostral

| Questão | Resposta / justificação |
|---|---|
| Dados críticos: pelo menos três conjuntos | |
| RPO e justificação | |
| RTO e justificação | |
| Tipo de cópia, frequência e destino | |
| Número de ficheiros verificados e resultado dos hashes | |
| Porque não basta listar o conteúdo do arquivo? | |

## T2 — Baseline e carga

| Indicador | Repouso | Sob carga | Hora / fonte |
|---|---|---|---|
| Número de CPUs | | | |
| Load average: 1 / 5 / 15 min | | | |
| CPU: utilização / idle | | | |
| Memória disponível | | | |
| Disco: capacidade e inodes utilizados | | | |
| Estado do Docker e portas em escuta | | | |
| Código HTTP / tempo de resposta CP4 | | | |

**Confirmação do fim da carga e interpretação das diferenças:** ____________________

**Porque pode o load average demorar a descer?** ____________________

| Limiar | Indicador / valor | Duração | Severidade | Justificação | Ação proposta |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |

## T3 — Site Nginx

| Campo | Resposta / evidência |
|---|---|
| Versão e estado do Nginx | |
| Nome do site e ficheiro de configuração | |
| Raiz e marcador do posto | |
| Resultado da validação e aplicação | |
| Pedido com nome, origem, código / conteúdo e hora | |
| Porque pode um pedido por IP selecionar outro site? | |

## T4 — Permissões e exposição

| Campo | Resposta / evidência |
|---|---|
| Conta dos processos worker do Nginx | |
| Donos e permissões relevantes | |
| Resultado do teste de leitura / escrita pela conta de serviço | |
| Regras UFW e origens autorizadas | |
| Pedido que confirma a continuidade do site | |

## T5 — HTTPS

| Campo | Resposta / evidência |
|---|---|
| Nome / SAN e emissor do certificado | |
| Validade e data de expiração | |
| Resultado da verificação com a CA | |
| Proteção da chave: apenas dono / permissões, sem conteúdo | |
| Resultado HTTPS com nome e CA, sem desativar verificação | |
| Resultado da redireção HTTP | |
| O que acontece num pedido por IP? Porquê? | |

## T6 — Diagnóstico web

| Falha | Sintoma | Evidência: fonte / consulta / hora | Hipótese e teste | Correção mínima | Reteste |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| Extensão, se realizada | | | | | |

## T7 — Primeiro backup

| Campo | Resposta / evidência |
|---|---|
| Versão e caminho do Restic | |
| Destino do repositório | |
| Referência de custódia do segredo, sem o revelar | |
| Snapshot: ID / host / caminhos / hora | |
| Evidência dos três conjuntos de dados | |
| Resultado da verificação do repositório | |
| O que falta demonstrar para provar a recuperação do serviço? | |

## T8 — Proteção do repositório

| Campo | Resposta / evidência |
|---|---|
| Donos / permissões do repositório e do ficheiro de segredo | |
| Teste de acesso como utilizador comum, sem sudo | |
| Resultado e código de saída com palavra-passe errada | |
| Limite em caso de perda do disco / VM | |
| Proteção adicional proposta | |

## T9 — Retenção simulada

| Política | Previsão: manter / remover | Resultado do dry-run | Justificação pelos motivos apresentados |
|---|---|---|---|
| Dois últimos snapshots | | | |
| Sete diários / quatro semanais | | | |

**Histórico disponível e diferenças entre previsão e resultado:** ____________________

## T10 — Automatização

| Campo | Resposta / evidência |
|---|---|
| Calendário e resultado da sua validação | |
| Serviço / timer e caminhos adaptados | |
| Próxima execução prevista | |
| Execução do serviço: hora / resultado / journal | |
| Snapshot novo com etiqueta timer | |
| Diferença entre timer ativo e backup executado | |

## T11 — Restauro controlado

| Campo | Resposta / evidência |
|---|---|
| Ficheiro de teste e referência do conteúdo | |
| Snapshot escolhido e justificação | |
| Sintoma e início da recuperação | |
| Destino de staging | |
| Comparação do conteúdo / dono / permissões | |
| Ficheiro promovido e resultado | |
| Teste HTTPS: origem / código / conteúdo / hora de recuperação | |
| Tempo observado e comparação com RTO de T1 | |
| Limpeza de staging / apoio recebido | |

## T12 — Host Zabbix

| Campo | Resposta / evidência |
|---|---|
| Estado e versão do Agent 2 | |
| Host / grupo / interface / template | |
| Modo de ligação e identidade pública PSK, sem valor secreto | |
| Disponibilidade do agente | |

| Métrica | Item consultado | Valor / unidade | Hora da amostra |
|---|---|---|---|
| CPU | | | |
| Memória | | | |
| Disco | | | |
| Uptime | | | |

## T13 — Serviço e triggers

| Campo | Resposta / evidência |
|---|---|
| Nome do cenário / URL / intervalo | |
| Código e conteúdo exigidos | |
| Verificação do certificado / nome / CA configurada | |
| Trigger do site: nome / condição / severidade / estado | |
| Limiar de T2 escolhido e item real do template | |
| Segundo trigger: condição / duração / severidade | |
| Dados recentes do cenário e respetivo instante | |

## T14 — Falha e recuperação

| Momento | Hora / fuso | Evidência |
|---|---|---|
| Falha provocada | | |
| PROBLEM no Zabbix | | |
| Serviço reposto e teste funcional | | |
| RESOLVED no Zabbix | | |

**Explicação dos intervalos observados:** ____________________

**Um problema no ecrã comprova uma notificação entregue? Que evidência seria necessária?** ____________________

## T15 — Monitorização e logs

| # | Família | Alvo / fonte / consulta | Hora da ocorrência ou amostra / fuso | O que demonstra e limites |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

**Registo da paragem / arranque do Nginx:** ____________________

**Registo dos pedidos do Zabbix:** ____________________

**Registo do acesso SSH:** ____________________

**Relação temporal entre as evidências e hora da consulta:** ____________________

## T16 — Relatório de incidente

| Etapa | Registo |
|---|---|
| Alerta / sintoma / impacto / instante | |
| Evidências de monitorização e logs: fonte / consulta / instante | |
| Hipótese 1 | |
| Hipótese 2 | |
| Teste que distingue as hipóteses e resultado | |
| Causa confirmada ou limites da conclusão | |
| Ação mínima aplicada e respetiva justificação | |
| Validação funcional independente | |
| Validação monitorizada: amostra nova / RESOLVED / instante | |
| Foi necessário backup? Porquê? | |
| Medida para evitar a repetição | |
| Estado final, apoio recebido e pendências | |

## T17 — Checklist de entrega

| Tarefa | Evidência principal | Concluída | Validada pelo formador |
|---|---|:---:|:---:|
| T0 | Origem / projeto / volume CP4 identificados e HTTP esperado | ☐ | ☐ |
| T1 | Decisão RPO/RTO e hashes após restauro | ☐ | ☐ |
| T2 | Baseline / carga e dois limiares | ☐ | ☐ |
| T3 | Site correto com nome e marcador | ☐ | ☐ |
| T4 | Leitura sem escrita e UFW revisto | ☐ | ☐ |
| T5 | HTTPS validado, redireção e prazo | ☐ | ☐ |
| T6 | Diagnóstico das duas falhas | ☐ | ☐ |
| T7 | Snapshot e consistência do repositório | ☐ | ☐ |
| T8 | Acessos protegidos e limites | ☐ | ☐ |
| T9 | Duas simulações de retenção explicadas | ☐ | ☐ |
| T10 | Timer, journal e snapshot novo | ☐ | ☐ |
| T11 | Ficheiro recuperado, teste funcional e tempo | ☐ | ☐ |
| T12 | Agente disponível e métricas recentes | ☐ | ☐ |
| T13 | Cenário e dois triggers | ☐ | ☐ |
| T14 | Quatro instantes e ciclo PROBLEM / RESOLVED | ☐ | ☐ |
| T15 | Três evidências de duas famílias | ☐ | ☐ |
| T16 | Relatório e recuperação comprovada | ☐ | ☐ |
| T17 | Revisão, entrega, fecho do posto e roteiro | ☐ | ☐ |

| Reposição / apoio recebido | Hora | Efeito / tarefa por concluir |
|---|---|---|
| | | |
| | | |

**Estado final do timer de treino:** ____________________

**Pendências e secções dos manuais a rever:** ____________________

**Confirmações finais:**

- [ ] As evidências identificam o meu posto e os instantes relevantes.
- [ ] Os apoios e as reposições estão identificados.
- [ ] A folha e as capturas não contêm segredos.
- [ ] Entreguei o trabalho pelo meio indicado pelo formador.
- [ ] Recebi o roteiro de estudo e respondi ao questionário de satisfação.
