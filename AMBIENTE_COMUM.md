# Mesmo ambiente para formador e formandos

O posto de demonstração do formador segue o mesmo modelo das VMs dos formandos. Os comandos dos exercícios, os nomes dos serviços e a estrutura das pastas são comuns. A identificação do posto, o seu IP e os segredos variam por máquina, como já acontece entre p1, p2 e p3.

| Elemento | Valor comum |
|---|---|
| Sistema | Ubuntu 26.04 LTS |
| Pasta CP4 | `$HOME/cp4` — com a conta ubuntu: `/home/ubuntu/cp4` |
| Compose | `$HOME/cp4/compose.yaml` |
| Projeto / serviço / contentor | `cp4` / `app` / `cp4-app-1` |
| Volume / destino | `cp4_dados` / `/dados` |
| HTTP da CP4 | `http://127.0.0.1:8000/` |
| Ficha carregada na shell | `$HOME/parametros-posto.sh` |
| Amostra T1 | `/srv/amostra-t1` |
| Site | `/var/www/$POSTO` |
| Configuração Nginx | `/etc/nginx/conf.d/$POSTO.conf` |
| Logs | `/var/log/nginx/$POSTO.access.log` e `$POSTO.error.log` |
| Certificados do site | `/etc/nginx/tls` |
| CA pública da sala | `/etc/ssl/lab/ca-lab.crt` |
| Disco / repositório de backup | `/srv/backup` / `/srv/backup/$POSTO` |
| Segredo Restic | `/root/.restic-$POSTO.pw` |
| Modelos T10 | `/opt/lab/modelos/backup-sessao.service` e `.timer` |
| Unidades instaladas em T10 | `/etc/systemd/system/backup-sessao.service` e `.timer` |
| Configuração / PSK do agente | `/etc/zabbix/zabbix_agent2.conf` / `zabbix_agent2.psk` |

`POSTO` é um parâmetro, não uma estrutura diferente: por exemplo, p1 usa `/var/www/p1` e o posto do formador usa `/var/www/formador`. Ambos executam os mesmos comandos com `$WEB_ROOT`, `$NGINX_INCLUDE` e os restantes parâmetros.

Nginx, Restic, UFW, systemd e Agent 2 executam no Ubuntu. Docker executa a CP4. O servidor Zabbix é o servidor comum da sala. Assim, `systemctl`, `journalctl`, os testes TLS e os comandos Restic usados no guia têm o mesmo significado nos dois ambientes.

## Preparar um posto

O [script comum](preparar-posto.sh) instala os pré-requisitos, reutiliza ou cria a CP4 a partir do [Compose canónico](cp4/compose.yaml), prepara a amostra T1, instala o certificado **público** da CA, configura o agente passivo e gera a ficha de parâmetros e os modelos T10.

Não executa a resolução de T3–T17: o site do posto, a emissão TLS, o repositório de treino, o timer e o registo do host no Zabbix são trabalhados pelos mesmos passos do [guia de resolução](formador/GUIA_RESOLUCAO.md).

Na VM Ubuntu, com uma cópia completa deste repositório e Docker/Compose disponíveis, substitui os marcadores pelos valores da ficha:

```bash
cd "$HOME/adm-srv"
sudo bash preparar-posto.sh instalar \
  --posto ID_DO_POSTO \
  --ip-zabbix IP_DO_SERVIDOR_ZABBIX \
  --ca-cert CAMINHO_DO_CERTIFICADO_PUBLICO
```

O disco de backup tem de estar montado em `/srv/backup`. O script também aceita `--disco-serial SERIAL` para montar um disco ext4 existente; só inicializa um disco sem partições, montagens ou assinaturas se acrescentares explicitamente `--inicializar-disco`. Nunca seleciona o disco pela posição `/dev/sda` ou `/dev/sdb`.

Os postos já preparados segundo o enunciado podem continuar a trabalhar. Não precisam de reinstalar o sistema para usar estes nomes.

## Adaptar a VM antiga do formador

Também podes executar a preparação diretamente dentro da VM Ubuntu, sem usar o agente QEMU: segue o [script direto e as instruções](formador/README.md#preparar-diretamente-a-vm-do-formador). Esse modo reutiliza Docker/Compose existentes e obtém a configuração da sala por SSH normal, ou recebe os parâmetros explicitamente.

No **Proxmox**, atualiza o script e executa `alinhar`:

```bash
cd /root
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/Skullclamp/adm-srv/main/formador/proxmox/criar-vm-formador.sh \
  -o criar-vm-formador.sh
bash criar-vm-formador.sh alinhar
```

O script usa o VMID e marcador privados já guardados. Obtém o IP do Zabbix de `/root/laboratorio/lab.conf` e o certificado público de `/root/laboratorio/segredos/ca-lab.crt`. Se estiverem noutro local, indica `--ip-zabbix IP` e `--ca-cert CAMINHO`. Não envia a chave privada da CA para a VM.

Acrescenta um disco de backup de 10 GB se o dispositivo `scsi1` estiver livre. Nesse caso pode reiniciar a VM para reconhecer o novo disco; uma sessão SSH aberta pode terminar. Se `scsi1` já for outro disco, interrompe para revisão, sem o substituir.

A adaptação guarda a configuração privada antiga em `/var/lib/adm-srv-posto/migracao-*`, para os contentores do projeto antigo e conserva todos os seus volumes. Copia os dados de `adm-srv-formador_cp4_dados` para `cp4_dados` e verifica hashes. Se os dois volumes já contiverem dados diferentes, interrompe: ambos ficam conservados e é necessário escolher a origem antes de continuar. Os backups Restic antigos permanecem no volume antigo, com o segredo guardado na cópia privada de configuração.

Depois da primeira cópia verificada, regista a identidade do volume em `/var/lib/adm-srv-posto/migracao-cp4.json`. Repetir a preparação conserva os dados atuais de CP4, incluindo alterações feitas durante a aula. Se o volume tiver sido substituído, interrompe para recuperar os dados antes de continuar. Uma preparação comum concluída pela versão anterior é reconhecida pelo seu registo de conclusão, sem voltar a copiar os dados antigos.

A stack antiga em `formador/docker-lab` fica como material de recuperação. O percurso de aula passa a usar a preparação comum.

## Executar os mesmos exercícios

Na shell **da VM Ubuntu**, tanto no formador como no formando:

```bash
source "$HOME/parametros-posto.sh"
validar_parametros
cd "$HOME/cp4"
sudo docker compose ps
```

Para copiar dados de CP4, o serviço é sempre `app`:

```bash
T1_DIR=$(mktemp -d "$HOME/t1-ensaio.XXXXXX")
sudo docker compose cp app:/dados "$T1_DIR/original"
```

No T1 do enunciado, a amostra fornecida é `/srv/amostra-t1`; o [guia](formador/GUIA_RESOLUCAO.md#t1--decisão-de-proteção-e-restauro-amostral) usa `AMOSTRA_ORIGEM` da mesma ficha. Escolhe a amostra pedida na tarefa e regista a origem usada.

Após a preparação, confirma com:

```bash
sudo bash "$HOME/adm-srv/preparar-posto.sh" verificar
```

Esta verificação confirma os pré-requisitos, CP4, amostra, CA, agente e disco. A monitorização central e o HTTPS do site são confirmados nas tarefas respetivas.

## Antes de publicar o site em T3

O Nginx tem de estar instalado e ativo no Ubuntu da VM. A secção [T3 do guia](formador/GUIA_RESOLUCAO.md#t3--publicar-o-site-nginx) inclui agora a verificação e instalação do pacote, o carregamento da ficha e a confirmação de `site-$POSTO.conf` antes de aplicar a configuração. O mesmo procedimento serve para formador e formandos.

Se aparecer `nginx: command not found`, conclui esse pré-requisito. Se faltar `parametros-posto.sh`, conclui a preparação comum. Se faltar o ficheiro de trabalho, completa o passo 2 de T3. A aplicação da configuração termina antes de alterar o destino quando faltam esses elementos.

## Validação da publicação

Foram executados testes de sintaxe Bash, igualdade entre o Compose do guia dos formandos e o ficheiro instalado, geração dos caminhos para p1/p2/formador, conservação de dados na migração e configuração Proxmox simulada. Não foi executada uma migração real nem uma criação de VM neste ambiente de preparação.

Consulta a [verificação de T0–T17 e dos scripts](formador/VERIFICACAO.md) para os casos verificados e os limites destes testes.
