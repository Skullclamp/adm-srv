# Administração Linux — Exercício final prático

**Documento do formando · Módulos M4–M8 · Duração: 8 horas**

Nesta sessão vais publicar um serviço web com HTTPS, proteger os seus dados, automatizar backups e usar monitorização e logs para resolver um incidente. **CP4** é a aplicação HTTP didática que serve de base ao trabalho: um serviço executado com Docker Compose e dados guardados num volume persistente. Nas VMs novas, prepara essa aplicação seguindo o [guia de criação e verificação da CP4](PREPARAR_CP4.md) antes de iniciar T0.

Realiza as tarefas **T0–T17** na ordem indicada. Para cada tarefa, responde às questões, recolhe as evidências pedidas e mostra o resultado ao formador. A avaliação desta sessão é **formativa, sem nota**.

Preenche a [folha de respostas e evidências](FOLHA_DE_RESPOSTAS.md). Podes descarregar uma cópia e preenchê-la localmente. Os manuais M4–M8 são fornecidos pelo formador para estudo autónomo depois da sessão.

## Antes de começar

- Confirma com o formador qual é o teu posto.
- A VM deve estar preparada pelo formador com as ferramentas e os materiais de apoio necessários às tarefas.
- Recebe a ficha de parâmetros, o certificado público da CA e os acessos do teu posto. A PSK e a palavra-passe do Zabbix são entregues à parte.
- No Windows, abre o PowerShell para entrar por SSH na VM. Executa os comandos Linux **dentro da sessão SSH**. Utiliza o browser do Windows para o frontend Zabbix.
- Mantém uma segunda sessão SSH ou o acesso à consola disponível para recuperação.
- Se um pré-requisito não estiver disponível, pede apoio ao formador antes de avançar.

## Ficha de parâmetros do posto

O formador entrega os parâmetros de execução à parte. Preenche-os na tua cópia local; esta publicação contém o enunciado e modelos em branco, sem valores da infraestrutura.

| Parâmetro | Valor atribuído pelo formador |
|---|---|
| Identificação e acesso ao posto | |
| Aplicação CP4 e dados persistentes | |
| Amostra para T1 | |
| Nome, raiz e configuração do site | |
| Marcador esperado no conteúdo | |
| Logs de acessos e de erros | |
| Certificado público da CA e diretório TLS | |
| Rede autorizada e portas atribuídas | |
| Repositório Restic e ficheiro protegido do segredo | |
| Calendário e modelos do timer de treino | |
| Frontend, host, grupo, template e identidade pública PSK no Zabbix | |

As credenciais e o valor da PSK são entregues pelo canal indicado pelo formador e não se registam nesta ficha.

## Regras de trabalho

1. Trabalha apenas na tua VM e nos recursos atribuídos.
2. Guarda uma cópia antes de alterar uma configuração. Valida a configuração Nginx antes de a aplicar.
3. Mantém o acesso SSH e limita a exposição às portas e origens necessárias.
4. Não coloques palavras-passe, chaves privadas ou valores de PSK nas respostas, capturas ou no GitHub. Entrega as evidências pelo meio indicado pelo formador.
5. As eliminações deste exercício limitam-se às amostras e aos ficheiros de teste indicados. No Restic, a retenção é apenas simulada com `forget --dry-run`; não uses `prune`.
6. Se uma tarefa não estiver concluída à hora de reposição, o formador fornece um estado de referência. Regista o apoio e continua a sequência.

## Cronograma

| Hora | Tarefa | Tema |
|---|---|---|
| 08:30–08:45 | T0 | Arranque e verificação CP4 |
| 08:45–09:15 | T1 | Decisão de proteção e restauro amostral |
| 09:15–09:45 | T2 | Baseline, carga e limiares |
| 09:45–10:15 | T3 | Publicação do site Nginx |
| 10:15–10:35 | T4 | Permissões e exposição |
| 10:35–11:15 | T5 | HTTPS com CA de laboratório |
| 11:15–11:45 | T6 | Diagnóstico de falhas web |
| 11:45–12:30 | T7 | Primeiro backup Restic |
| 12:30–12:45 | T8 | Proteção do repositório |
| 12:45–13:00 | T9 | Retenção simulada |
| 13:00–14:00 | — | Almoço |
| 14:00–14:25 | T10 | Automatização com systemd timer |
| 14:25–15:00 | T11 | Restauro controlado |
| 15:00–15:25 | T12 | Registo do host no Zabbix |
| 15:25–15:50 | T13 | Serviço HTTPS e triggers |
| 15:50–16:15 | T14 | Falha e recuperação observadas |
| 16:15–16:35 | T15 | Pesquisa e correlação de logs |
| 16:35–17:15 | T16 | Incidente integrado |
| 17:15–17:30 | T17 | Fecho e entrega |

## T0 — Arranque e verificação do ponto de partida

**M4 · 15 minutos**

1. Entra na VM por SSH. Identifica o hostname, o utilizador, a versão do sistema e o tempo desde o arranque.
2. Identifica a origem da CP4: criada por ti nesta VM, retomada ou fornecida pelo formador. Se estiver em falta, usa o [guia de preparação da CP4](PREPARAR_CP4.md) com o apoio do formador antes de continuar.
3. Verifica o projeto Docker Compose, o serviço e o contentor da CP4. Identifica o volume persistente e a sua montagem.
4. Testa o endpoint CP4 a partir da própria VM. Que código HTTP e que conteúdo obténs?
5. Regista a prova de persistência feita na preparação: o que aconteceu aos dados depois de substituir o contentor? Se usares uma referência fornecida, identifica essa origem e o que verificaste pessoalmente.
6. Se a aplicação não responder como esperado, conserva o erro e apresenta-o ao formador. Usa o procedimento de recuperação do guia sem remover o volume.

**Evidência e critério de sucesso:** identidade da VM, origem da CP4, projeto/contentor/volume identificados e resposta HTTP esperada. **Reposição: 08:45.**

## T1 — Decisão de proteção e restauro de uma amostra

**M4 · 30 minutos**

1. Identifica pelo menos três conjuntos de dados críticos do servidor. Justifica a escolha.
2. Define um **RPO** e um **RTO**. Quanta perda de dados é aceitável e em quanto tempo deve o serviço ser recuperado?
3. Propõe tipo de cópia, frequência e destino compatíveis com essas metas.
4. Copia a amostra fornecida para uma área de trabalho na tua pasta pessoal. Regista o hash SHA-256 de todos os ficheiros e cria um arquivo da amostra.
5. Confirma que o arquivo é legível. Elimina **apenas a cópia de trabalho da amostra**, restaura-a e compara todos os hashes.
6. Porque é que listar o conteúdo do arquivo, por si só, não prova que a cópia é restaurável?

**Evidência e critério de sucesso:** decisão justificada, quantidade de ficheiros verificados e verificação de todos os hashes com resultado `OK`.

## T2 — Baseline, carga e limiares

**M5 · 30 minutos**

1. Regista o estado inicial do servidor: load average, número de CPUs, utilização de CPU, memória disponível, capacidade e inodes do disco, estado do Docker, portas em escuta e tempo de resposta HTTP da aplicação CP4.
2. Com orientação do formador, provoca carga de CPU limitada a **90 segundos**, com um processo por CPU. Durante a carga, repete as observações de CPU, load average e tempo de resposta.
3. Confirma que os processos de carga terminaram. O que mudou em relação à baseline?
4. Porque é que o load average pode continuar elevado depois de a carga terminar?
5. Propõe **dois limiares de alerta**. Para cada um, indica indicador, valor, duração, severidade, justificação e ação a tomar.

**Evidência e critério de sucesso:** tabela repouso/carga preenchida e dois limiares ligados às observações. Guarda-os para T13.

## T3 — Publicar o site com Nginx

**M6 · 30 minutos**

1. Confirma a versão e o estado do Nginx.
2. Cria uma página inicial identificada com o teu posto e um ficheiro `estado.html` com o marcador atribuído.
3. Configura um servidor virtual com o nome, a porta HTTP, a raiz e os logs atribuídos ao teu posto.
4. Valida a configuração e aplica-a. Testa o pedido com o nome correto a partir da VM e, se disponível, de um cliente da LAN.
5. Explica porque é que um pedido apenas por IP pode ser servido por outro bloco `server`.

**Evidência e critério de sucesso:** o pedido com o nome do site devolve o marcador correto. Se um pedido imediatamente após o reload falhar, aguarda 1–2 segundos e repete antes de alterar a configuração. **Reposição: 10:35.**

## T4 — Permissões e exposição

**M6 · 20 minutos**

1. Identifica a conta usada pelos processos worker do Nginx, que atendem HTTP/HTTPS. Aqui, worker não significa um nó do Kubernetes.
2. Verifica os donos e as permissões do caminho até `estado.html`. A conta de serviço consegue ler o ficheiro? Consegue alterá-lo?
3. Ajusta o necessário para permitir leitura e travessia, preservando o conteúdo contra escrita pela conta de serviço. Não uses permissões `777`.
4. Revê o UFW. Mantém a regra SSH e a recolha do Zabbix; permite as portas do site apenas à rede de laboratório.
5. Confirma que o site continua acessível.

**Evidência e critério de sucesso:** leitura permitida, escrita negada à conta de serviço, regras de firewall coerentes e resposta correta do site.

## T5 — HTTPS de laboratório

**M6 · 40 minutos**

1. Gera na tua VM uma chave privada e um pedido de certificado (**CSR**) com o nome do site no **SAN**.
2. Entrega apenas o CSR ao formador. Recebe o certificado assinado pela CA de laboratório.
3. Antes de o instalar, identifica emissor, nome/SAN, validade e resultado da verificação com a CA.
4. Protege a chave privada, configura HTTPS e redireciona os pedidos HTTP para HTTPS.
5. Valida a resposta, o nome e a confiança com o certificado público da CA, sem desativar a verificação TLS. Confirma também a redireção e a data de expiração.
6. O que acontece se pedires o site por IP em vez do nome certificado? Explica.

**Evidência e critério de sucesso:** marcador correto por HTTPS, redireção HTTP `301`, validação da cadeia com sucesso e prazo identificado. **Reposição: 11:15.**

## T6 — Diagnóstico de falhas web

**M6 · 30 minutos**

O formador introduz **duas falhas**, uma de cada vez. Para cada falha:

1. Descreve o sintoma e o impacto no pedido ao site.
2. Recolhe evidência nos logs e na configuração ou nos acessos relevantes. Indica fonte, consulta e instante.
3. Formula uma hipótese e escolhe um teste para a confirmar.
4. Aplica a correção mínima. Se alterares configuração, valida-a antes de a aplicar.
5. Repete o pedido inicial e comprova a recuperação.

**Extensão, se terminares cedo:** publica a aplicação CP4 através de um reverse proxy no percurso indicado pelo formador, mantendo o site estático e o HTTPS. Depois pede ao formador uma falha adicional nesse percurso e diagnostica-a.

**Evidência e critério de sucesso:** duas linhas completas de sintoma → evidência → hipótese → teste → correção → validação. **Reposição: 11:45.**

## T7 — Primeiro backup com Restic

**M7 · 45 minutos**

1. Confirma a versão e o caminho do Restic e o destino do repositório atribuído.
2. Cria um ficheiro de palavra-passe protegido e segue o procedimento de custódia indicado pelo formador, sem expor o segredo.
3. Inicializa o repositório e faz backup de **conteúdo do site, configuração do Nginx e dados persistentes da aplicação CP4**, com a etiqueta `sessao-final`.
4. Lista os snapshots, identifica o snapshot criado, consulta o conteúdo e verifica a consistência do repositório.
5. A verificação do repositório prova, por si só, que consegues recuperar o serviço? O que falta demonstrar?

**Evidência e critério de sucesso:** ID do snapshot, presença dos três conjuntos de dados e verificação sem erros. Não registes a palavra-passe.

## T8 — Proteção do repositório

**M7 · 15 minutos**

1. Verifica donos e permissões do repositório e do ficheiro de palavra-passe.
2. Confirma, sem usar privilégios administrativos no teste de leitura, que o utilizador comum não consegue ler o segredo nem aceder ao repositório.
3. Faz uma tentativa controlada de consulta com uma palavra-passe errada. Regista o resultado e o código de saída.
4. Explica o limite desta proteção se o disco ou a VM que contém o repositório se perder. Que proteção adicional proporias?

**Evidência e critério de sucesso:** acessos mínimos demonstrados, tentativa com segredo errado rejeitada e limite descrito.

## T9 — Retenção simulada

**M7 · 15 minutos**

1. Cria mais dois snapshots do mesmo conjunto de caminhos, alterando o conteúdo entre as cópias.
2. Prevê quantos snapshots seriam mantidos por cada política: **os dois últimos** e **sete diários/quatro semanais**.
3. Simula as duas políticas com `forget --dry-run`. Não removas snapshots nem executes `prune`.
4. Compara a previsão com o resultado. Usa os motivos apresentados pelo Restic para justificar quais seriam mantidos ou removidos.

**Evidência e critério de sucesso:** resultados das duas simulações e explicação das diferenças, considerando o histórico disponível.

## T10 — Automatizar com systemd timer

**M7 · 25 minutos**

1. Valida a expressão de calendário atribuída.
2. A partir dos modelos fornecidos, adapta o serviço e o timer de treino aos caminhos do teu posto. O backup deve incluir os mesmos três conjuntos de T7 e as etiquetas `sessao-final` e `timer`.
3. Ativa o agendamento e força uma execução do serviço.
4. Confirma a próxima execução prevista, o resultado no journal e a existência de um snapshot novo com a etiqueta `timer`.
5. «O timer está ativo» e «o backup foi feito» demonstram a mesma coisa? Justifica.

**Evidência e critério de sucesso:** agendamento visível, execução bem-sucedida no journal e snapshot correspondente.

## T11 — Restauro controlado

**M7 · 35 minutos**

1. Cria `teste-restauro.html` no teu site, com um conteúdo identificável. Faz backup e regista o snapshot.
2. Elimina apenas esse ficheiro de teste. Confirma o sintoma por HTTPS e regista a hora de início da recuperação.
3. Escolhe o snapshot adequado e restaura o ficheiro numa área de staging, sem sobrepor diretamente o sistema em utilização.
4. Compara conteúdo, dono e permissões. Promove apenas o ficheiro necessário para o destino correto.
5. Valida o conteúdo por HTTPS e regista a hora de recuperação funcional. Compara o tempo observado com o RTO definido em T1.
6. Remove a área de staging usada no exercício.

**Evidência e critério de sucesso:** snapshot justificado, ficheiro original recuperado, resposta HTTP `200` com o conteúdo esperado e tempo de recuperação registado. **Reposição: 15:00.**

## T12 — Registar o teu servidor no Zabbix

**M8 · 25 minutos**

1. Confirma que o Agent 2 está instalado e ativo no teu posto.
2. Com a tua conta de frontend, cria o host no grupo atribuído. Usa o nome lógico, o endereço e a interface Agent com a porta indicada pelo formador.
3. Associa o template **Linux by Zabbix agent**, na variante passiva.
4. Configura a ligação ao host com **PSK**, usando a identidade e o valor entregues pelo formador. Não deixes a ligação sem encriptação.
5. Confirma a disponibilidade do agente e encontra valores recentes de CPU, memória, disco e uptime em *Monitoring → Latest data*.

**Evidência e critério de sucesso:** agente disponível e quatro famílias de métricas com instantes recentes. As capturas devem ocultar qualquer segredo.

## T13 — Verificação do serviço HTTPS e triggers

**M8 · 25 minutos**

1. Cria no teu host um cenário web com o nome atribuído, intervalo de **1 minuto** e uma consulta HTTPS ao ficheiro de estado. Exige código `200` e o marcador de conteúdo atribuído ao posto.
2. Confirma com o formador a configuração de confiança na CA e a verificação do nome/certificado no cenário.
3. Cria um trigger de severidade **High**, identificado com o teu posto, que detete a falha do cenário.
4. Cria um segundo trigger com um dos limiares propostos em T2. Usa o construtor de expressões e um item real do template.
5. Confirma dados recentes do cenário e o estado saudável antes de provocar falhas.

**Evidência e critério de sucesso:** cenário com dados, trigger do site em estado OK e trigger do limiar T2 associado a um item existente. **Reposição: 15:50.**

## T14 — Falha e recuperação observadas

**M8 · 25 minutos**

1. Regista a hora e interrompe o Nginx da tua VM.
2. Observa o problema no Zabbix e regista a hora em que foi detetado.
3. Repõe o serviço e regista a hora. Confirma a resposta HTTPS.
4. Aguarda a recuperação no Zabbix e regista a hora do estado **RESOLVED**.
5. Explica o intervalo entre falha, deteção e recuperação observada.
6. Um problema apresentado no ecrã significa que foi entregue uma notificação a alguém? Que evidência seria necessária?

**Evidência e critério de sucesso:** quatro instantes registados, validação funcional e ciclo **PROBLEM → RESOLVED** comprovado.

## T15 — Encontrar a falha nos logs

**M8 · 20 minutos**

1. Localiza a paragem e o arranque de T14 no journal do Nginx.
2. Encontra os pedidos do Zabbix no log de acessos ao site.
3. Localiza um acesso SSH ao teu posto e identifica a fonte consultada.
4. Seleciona **pelo menos três evidências de duas famílias: monitorização e logs**. Para cada uma, indica alvo, fonte, consulta, instante/fuso e o que demonstra.
5. Explica como os instantes das evidências se relacionam. Distingue a hora da ocorrência da hora em que consultaste os dados.

**Evidência e critério de sucesso:** três observações pertinentes, incluindo monitorização e logs, com interpretação e contexto temporal.

## T16 — Incidente integrado

**M8 · 40 minutos**

O formador introduz uma falha desconhecida no teu servidor. Investiga antes de intervir; não reinicies a VM nem restaures dados sem diagnóstico.

1. Identifica o alerta, o sintoma e o impacto.
2. Recolhe evidências de monitorização e logs com fonte e instante.
3. Formula pelo menos **duas hipóteses** e escolhe um teste que permita distingui-las.
4. Regista o resultado do teste e aplica a ação mínima fundamentada nas evidências.
5. Confirma a recuperação por um teste funcional independente e pela monitorização.
6. Explica se foi necessário usar o backup e porquê.
7. Propõe uma medida que reduza a probabilidade de repetição e regista eventuais limites da recuperação.

**Evidência e critério de sucesso:** serviço recuperado, estado RESOLVED no Zabbix e relatório que liga hipóteses, testes e ações às evidências.

## T17 — Fecho

**M8 · 15 minutos**

1. Revê a folha de respostas e evidências. Confirma que não contém segredos.
2. Assinala as tarefas concluídas, os apoios recebidos, as reposições e o que ficou pendente.
3. Desativa o timer de treino quando o formador indicar.
4. Entrega as evidências pelo meio indicado e responde ao questionário de satisfação fornecido.
5. Identifica no roteiro de estudo os conteúdos que precisas de rever.

**Evidência e critério de sucesso:** folha revista e entregue, estado final do posto confirmado e roteiro de estudo recebido.

## Roteiro de estudo autónomo

Consulta os manuais fornecidos pelo formador. Começa pelas secções que consolidam as tarefas realizadas e depois pelas que complementam a sessão.

| Manual | Consolida | Complementa |
|---|---|---|
| M4 — Estratégias de backup | M4.1, M4.2, M4.6 | M4.3, M4.4, M4.5, M4.7 |
| M5 — Monitorização e desempenho | M5.1–M5.5 | M5.6, M5.7 |
| M6 — Servidores web | M6.2, M6.3, M6.4, M6.6, M6.8 | M6.1, M6.5, M6.7, M6.9 |
| M7 — Sistemas de backup | M7.2, M7.3, M7.4, M7.5, M7.7 | M7.1, M7.6, M7.8 |
| M8 — Monitorização e logs | M8.2, M8.4, M8.5, M8.6, M8.7 | M8.1, M8.3, M8.8 |
