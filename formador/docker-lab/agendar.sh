#!/bin/sh
# Agendamento do laboratório Docker; o primeiro backup é criado pelo script principal.
set -u
intervalo=${BACKUP_INTERVAL:-1800}
case "$intervalo" in
    ''|*[!0-9]*) echo 'BACKUP_INTERVAL deve ser um número de segundos.' >&2; exit 1 ;;
esac
[ "$intervalo" -ge 30 ] && [ "$intervalo" -le 86400 ] || exit 1

while :; do
    sleep "$intervalo"
    printf '\n[%s] Início do backup automático\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if restic --retry-lock 1m backup /origens/site /origens/nginx /origens/cp4 /origens/tls \
        --host formador-docker --tag laboratorio --tag automatico; then
        printf '[%s] Backup concluído\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
        printf '[%s] FALHA no backup; consultar este log e o repositório.\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
    fi
done
