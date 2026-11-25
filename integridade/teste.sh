#!/usr/bin/env bash
set -euo pipefail
umask 077
export LC_ALL=C

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work_dir=$(mktemp -d /tmp/isp-integridade-teste.XXXXXXXX)
trap 'rm -rf -- "$work_dir"' EXIT
samples="$work_dir/amostras"
state="$work_dir/estado"
mkdir -m 700 -- "$samples"
printf 'demo:x:1600:1600:Conta ficticia:/nonexistent:/bin/false\n' > "$samples/passwd"
printf 'demo:!:20000:0:99999:7:::\n' > "$samples/shadow"

write_rules() {
    local policy=$1 packets=$2 bytes=$3 time=$4
    cat > "$samples/iptables-save.txt" <<EOF
# Generated from a synthetic ruleset at $time
*filter
:INPUT $policy [$packets:$bytes]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
[$packets:$bytes] -A INPUT -i lo -j ACCEPT
COMMIT
# Completed at $time
EOF
}

assert_run() {
    local expected=$1 actual=0
    shift
    printf '\n$'
    printf ' %q' "$@"
    printf '\n'
    output=$("$@" 2>&1) || actual=$?
    printf '%s\n[exit=%s, esperado=%s]\n' "$output" "$actual" "$expected"
    [[ $actual == "$expected" ]]
}

printf 'Inicio UTC: %s\n' "$(date -u +%FT%TZ)"
monitor=(bash "$source_dir/monitor.sh" --estado "$state" --amostras "$samples")
write_rules DROP 0 0 00:00:00
assert_run 0 "${monitor[@]}" init
assert_run 0 "${monitor[@]}" check
for target in /etc/passwd /etc/shadow 'iptables-save(filter)'; do
    grep -Fq "status=OK alvo=$target" <<< "$output"
done
assert_run 0 stat -c '%a %n' "$state" "$state/referencia.sha256" "$state/auditoria.log" "$state/operacao.lock"
[[ $(stat -c '%a' "$state") == 700 ]]
for file in referencia.sha256 auditoria.log operacao.lock; do
    [[ $(stat -c '%a' "$state/$file") == 600 ]]
done
baseline=$(sha256sum < "$state/referencia.sha256")
assert_run 2 "${monitor[@]}" init
grep -Fq 'motivo=referencia_ja_existe' <<< "$output"
assert_run 2 "${monitor[@]}" update

printf '\nAlteracao controlada apenas de datas e contadores no snapshot de exemplo\n'
write_rules DROP 17 1360 00:00:59
assert_run 0 "${monitor[@]}" check
grep -Fq 'status=OK alvo=iptables-save(filter)' <<< "$output"

printf '\nAlteracoes controladas nos tres arquivos de amostra em /tmp\n'
printf 'teste:x:1601:1601:Outra conta ficticia:/nonexistent:/bin/false\n' >> "$samples/passwd"
printf 'teste:!:20000:0:99999:7:::\n' >> "$samples/shadow"
write_rules ACCEPT 17 1360 00:01:00
assert_run 1 "${monitor[@]}" check
for target in /etc/passwd /etc/shadow 'iptables-save(filter)'; do
    grep -Fq "status=ALERTA alvo=$target motivo=sha256_divergente" <<< "$output"
done
assert_run 1 "${monitor[@]}" watch 1 3
[[ $(grep -c 'status=CICLO' <<< "$output") == 3 ]]
[[ $(grep -c 'status=ALERTA' <<< "$output") == 9 ]]
[[ $(sha256sum < "$state/referencia.sha256") == "$baseline" ]]
assert_run 0 "${monitor[@]}" update --confirmar
assert_run 0 "${monitor[@]}" check
[[ $(sha256sum < "$state/referencia.sha256") != "$baseline" ]]
legacy_state="$work_dir/estado-original"
mkdir -m 700 -- "$legacy_state"
sed '1c isp-integridade-v1 amostras' "$state/referencia.sha256" > "$legacy_state/referencia.sha256"
legacy=(bash "$source_dir/monitor.sh" --estado "$legacy_state" --amostras "$samples")
assert_run 0 "${legacy[@]}" check
assert_run 0 "${legacy[@]}" update --confirmar
grep -q '^isp-integridade-v2 amostras ' "$legacy_state/referencia.sha256"
assert_run 0 "${legacy[@]}" check
printf 'Referencia v1 lida e migrada por atualizacao explicita.\n'
assert_run 124 timeout 2s "${monitor[@]}" watch 30
grep -Fq 'status=ENCERRADO alvo=monitor motivo=sinal' <<< "$output"

printf '\nRegressao de auditoria: falha antes da troca deve preservar a referencia\n'
mock="$work_dir/mock"
mkdir -- "$mock"
printf '#!/bin/sh\nexit 1\n' > "$mock/tee"
chmod 700 "$mock/tee"
before_failure=$(sha256sum < "$state/referencia.sha256")
printf 'outro:x:1602:1602:Conta de regressao:/nonexistent:/bin/false\n' >> "$samples/passwd"
assert_run 2 env PATH="$mock:$PATH" "${monitor[@]}" update --confirmar
if [[ $(sha256sum < "$state/referencia.sha256") != "$before_failure" ]]; then
    printf 'FALHA DE REGRESSAO: o comando retornou erro, mas a referencia foi substituida.\n' >&2
    exit 1
fi
assert_run 1 "${monitor[@]}" check
grep -Fq 'status=ALERTA alvo=/etc/passwd' <<< "$output"

printf '\nRegressao de auditoria: permissoes inseguras impedem a troca\n'
chmod 644 "$state/auditoria.log"
assert_run 2 "${monitor[@]}" update --confirmar
grep -Fq 'Arquivo de estado sem protecao: auditoria.log' <<< "$output"
[[ $(sha256sum < "$state/referencia.sha256") == "$before_failure" ]]
chmod 600 "$state/auditoria.log"

printf '\nRegressao de auditoria: falha na troca preserva a referencia e registra abortamento\n'
rename_mock="$work_dir/rename-mock"
mkdir -- "$rename_mock"
printf '#!/bin/sh\nexit 1\n' > "$rename_mock/mv"
chmod 700 "$rename_mock/mv"
assert_run 2 env PATH="$rename_mock:$PATH" "${monitor[@]}" update --confirmar
grep -Fq 'status=REFERENCIA_ABORTADA' <<< "$output"
[[ $(sha256sum < "$state/referencia.sha256") == "$before_failure" ]]

printf '\nRegressao de auditoria: falha apos a troca informa o commit e permite conciliacao\n'
real_tee=$(command -v tee)
cat > "$mock/tee" <<'EOF'
#!/bin/sh
record=$(cat) || exit 1
case $record in
    *' status=REFERENCIA_ATUALIZADA alvo=referencia '*) exit 1 ;;
esac
printf '%s\n' "$record" | "$REAL_TEE" "$@"
EOF
chmod 700 "$mock/tee"
assert_run 0 env PATH="$mock:$PATH" REAL_TEE="$real_tee" "${monitor[@]}" update --confirmar
grep -Fq 'confirmacao de auditoria pendente' <<< "$output"
[[ $(sha256sum < "$state/referencia.sha256") != "$before_failure" ]]
read -r _format _scope tx < "$state/referencia.sha256"
grep -Fq "status=REFERENCIA_PREPARADA alvo=referencia transacao=$tx operacao=REFERENCIA_ATUALIZADA" "$state/auditoria.log"
if grep -Fq "status=REFERENCIA_ATUALIZADA alvo=referencia transacao=$tx" "$state/auditoria.log"; then
    printf 'FALHA DE REGRESSAO: a confirmacao simulada nao falhou.\n' >&2
    exit 1
fi
assert_run 0 "${monitor[@]}" check
grep -Fq "status=REFERENCIA_RECUPERADA alvo=referencia transacao=$tx" <<< "$output"
assert_run 0 "${monitor[@]}" check
[[ $(grep -Fc "status=REFERENCIA_RECUPERADA alvo=referencia transacao=$tx" "$state/auditoria.log") == 1 ]]

printf '\nEventos gravados no log protegido\n'
for target in /etc/passwd /etc/shadow 'iptables-save(filter)'; do
    grep -Fm 1 "status=ALERTA alvo=$target" "$state/auditoria.log"
done
grep -Fm 1 'status=REFERENCIA_ATUALIZADA alvo=referencia' "$state/auditoria.log"
printf 'TESTES DE INTEGRIDADE CONCLUIDOS\n'
