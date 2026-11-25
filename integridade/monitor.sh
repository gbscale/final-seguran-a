#!/usr/bin/env bash
# Verifica por SHA-256 as contas locais e a tabela IPv4 filter do roteador ISP.
set -euo pipefail
umask 077
export LC_ALL=C

usage() {
    printf '%s\n' 'Uso: bash monitor.sh [--estado DIR] [--amostras DIR] init|check|update --confirmar|watch SEGUNDOS [CICLOS]' >&2
    exit 2
}

fail() {
    printf 'isp-integridade: %s\n' "$*" >&2
    exit 2
}

state_dir=''
samples=''
while (( $# )); do
    case $1 in
        --estado) [[ $# -ge 2 && -n $2 ]] || usage; state_dir=$2; shift 2 ;;
        --amostras) [[ $# -ge 2 && -n $2 ]] || usage; samples=$2; shift 2 ;;
        *) break ;;
    esac
done

action=${1:-}
case $action in
    init|check) [[ $# == 1 ]] || usage ;;
    update) [[ $# == 2 && $2 == --confirmar ]] || usage ;;
    watch)
        [[ $# == 2 || $# == 3 ]] || usage
        [[ $2 =~ ^[1-9][0-9]{0,5}$ && ${3:-1} =~ ^[1-9][0-9]{0,5}$ ]] || usage
        interval=$2
        cycles=${3:-0}
        ;;
    *) usage ;;
esac

scope=roteador
if [[ -n $samples ]]; then
    [[ -n $state_dir && -d $samples ]] || fail 'Use um diretorio --estado separado para as amostras.'
    samples=$(cd -P -- "$samples" && pwd) || fail 'Diretorio de amostras indisponivel.'
    scope=amostras
else
    [[ $EUID == 0 && -f /.dockerenv && $(hostname) == ubuntu-router ]] ||
        fail 'A leitura real exige root no conteiner Docker ubuntu-router.'
    state_dir=${state_dir:-/var/lib/isp-integridade}
fi

reference=referencia.sha256
audit_file=auditoria.log
lock_file=operacao.lock
targets=(passwd shadow iptables-filter)
declare -A known

private_file() {
    [[ -f $1 && ! -L $1 && $(stat -c '%u:%a:%h' -- "$1") == "$EUID:600:1" ]]
}

if [[ $action == init && ! -e $state_dir && ! -L $state_dir ]]; then
    mkdir -m 700 -- "$state_dir" || [[ -d $state_dir ]] || fail 'Nao foi possivel criar o diretorio de estado.'
fi
[[ -d $state_dir && ! -L $state_dir ]] || fail 'Diretorio de estado ausente. Execute init primeiro.'
cd -P -- "$state_dir" || fail 'Diretorio de estado indisponivel.'
[[ $(stat -c '%u:%a' -- .) == "$EUID:700" ]] || fail 'O estado precisa pertencer ao executor e ter modo 0700.'
for file in "$lock_file" "$audit_file"; do
    if [[ ! -e $file && ! -L $file ]]; then
        (set -C; : > "$file") 2>/dev/null || true
    fi
    private_file "$file" || fail "Arquivo de estado sem protecao: $file."
done

event_line() {
    local timestamp
    timestamp=$(date -u +%FT%TZ) || return 2
    printf '%s status=%s alvo=%s%s\n' "$timestamp" "$1" "$2" "${3:+ $3}"
}

log_event() {
    event_line "$@" | tee -a -- "$audit_file"
}

audit_reference() {
    local entry
    private_file "$audit_file" && [[ -w $audit_file ]] || return 2
    entry=$(event_line "$1" referencia "$2") || return 2
    # A linha vazia separa um novo registro de uma escrita anterior parcial.
    printf '\n%s\n' "$entry" | tee -a -- "$audit_file" > /dev/null || return 2
    sync -d -- "$audit_file" || return 2
    printf '%s\n' "$entry" || true
}

label() {
    case $1 in
        iptables-filter) printf 'iptables-save(filter)' ;;
        *) printf '/etc/%s' "$1" ;;
    esac
}

filter_snapshot() {
    # Comentários de geração e contadores mudam com o tempo ou o tráfego.
    # Preserve políticas, ordem das regras e comentários que pertencem às regras.
    if [[ $scope == amostras ]]; then
        cat -- "$samples/iptables-save.txt"
    else
        iptables-save -t filter
    fi | awk '
        /^[[:space:]]*(#|$)/ { next }
        /^\*/ { tables++; if ($0 == "*filter") filter++ }
        /^COMMIT$/ { commits++ }
        /^:INPUT[[:blank:]]/ { input++ }
        /^:FORWARD[[:blank:]]/ { forward++ }
        /^:OUTPUT[[:blank:]]/ { output++ }
        /^:/ { sub(/\[[0-9]+:[0-9]+\]$/, "[0:0]") }
        /^\[[0-9]+:[0-9]+\][[:blank:]]+-A[[:blank:]]/ { sub(/^\[[0-9]+:[0-9]+\][[:blank:]]+/, "") }
        { print }
        END { if (tables != 1 || filter != 1 || commits != 1 || input != 1 || forward != 1 || output != 1) exit 1 }
    '
}

current_hash() {
    local target=$1 mode=$2 sum snapshot path
    if [[ $target == iptables-filter ]]; then
        snapshot=$(filter_snapshot) || return 2
        if [[ $scope == roteador && $mode == reference ]]; then
            grep -q '^:INPUT DROP ' <<< "$snapshot" && grep -q '^:FORWARD DROP ' <<< "$snapshot" &&
                grep -q '^:SHOZZ_SSH_RATE ' <<< "$snapshot" || return 2
        fi
        sum=$(sha256sum <<< "$snapshot") || return 2
    else
        path="${samples:-/etc}/$target"
        [[ -f $path && -r $path ]] || return 2
        sum=$(sha256sum < "$path") || return 2
    fi
    printf '%s\n' "${sum%% *}"
}

read_reference() {
    private_file "$reference" || return 2
    local -a lines
    mapfile -t lines < "$reference" || return 2
    [[ -n ${lines[0]-} && ${#lines[@]} == 4 ]] || return 2
    reference_tx=''
    if [[ ${lines[0]} != "isp-integridade-v1 $scope" ]]; then
        local header_pattern="^isp-integridade-v2 $scope ([A-Za-z0-9]{16})$"
        [[ ${lines[0]} =~ $header_pattern ]] || return 2
        reference_tx=${BASH_REMATCH[1]}
    fi
    local i target digest
    for i in "${!targets[@]}"; do
        target=${targets[i]}
        digest=${lines[i+1]#"$target "}
        [[ $digest =~ ^[0-9a-f]{64}$ && ${lines[i+1]} == "$target $digest" ]] || return 2
        known[$target]=$digest
    done
}

recover_audit() {
    [[ -n $reference_tx ]] || return 0
    if grep -Eq "^[^[:space:]]+ status=REFERENCIA_(CRIADA|ATUALIZADA|RECUPERADA) alvo=referencia transacao=$reference_tx$" "$audit_file"; then
        return 0
    fi
    if ! sync -- . || ! audit_reference REFERENCIA_RECUPERADA "transacao=$reference_tx"; then
        printf 'isp-integridade: referencia ja efetivada (transacao=%s); confirmacao de auditoria ainda pendente.\n' "$reference_tx" >&2
        return 2
    fi
}

write_reference() (
    local status=$1 tmp tx header target sum active_header
    tmp=$(mktemp .referencia.XXXXXXXXXXXXXXXX) || return 2
    trap 'rm -f -- "$tmp"' EXIT
    tx=${tmp#.referencia.}
    header="isp-integridade-v2 $scope $tx"
    printf '%s\n' "$header" > "$tmp" || return 2
    for target in "${targets[@]}"; do
        if ! sum=$(current_hash "$target" reference); then
            log_event ERRO "$(label "$target")" 'motivo=referencia_nao_coletada'
            return 2
        fi
        printf '%s %s\n' "$target" "$sum" >> "$tmp" || return 2
    done
    sync -d -- "$tmp" || return 2
    if ! audit_reference REFERENCIA_PREPARADA "transacao=$tx operacao=$status"; then
        printf 'isp-integridade: falha na preparacao da auditoria; referencia preservada.\n' >&2
        return 2
    fi
    # A troca no mesmo diretório é o commit. O ID acompanha a referência.
    if ! mv -T -- "$tmp" "$reference"; then
        if ! { [[ -f $reference ]] && IFS= read -r active_header < "$reference" && [[ $active_header == "$header" ]]; }; then
            audit_reference REFERENCIA_ABORTADA "transacao=$tx motivo=troca_falhou" || true
            printf 'isp-integridade: nao foi possivel trocar a referencia.\n' >&2
            return 2
        fi
    fi
    if ! sync -- . || ! audit_reference "$status" "transacao=$tx"; then
        printf 'isp-integridade: referencia efetivada (transacao=%s); confirmacao de auditoria pendente.\n' "$tx" >&2
    fi
    return 0
)

check_reference() {
    local target sum result=0
    for target in "${targets[@]}"; do
        if ! sum=$(current_hash "$target" check); then
            log_event ERRO "$(label "$target")" 'motivo=coleta_falhou' || return 2
            result=2
        elif [[ $sum != "${known[$target]}" ]]; then
            log_event ALERTA "$(label "$target")" 'motivo=sha256_divergente' || return 2
            if [[ $result == 0 ]]; then result=1; fi
        else
            log_event OK "$(label "$target")" || return 2
        fi
    done
    return "$result"
}

locked() (
    local operation=$1
    exec 9>> "$lock_file" || return 2
    if ! flock -w 5 9; then
        log_event ERRO monitor 'motivo=lock_indisponivel'
        return 2
    fi
    if [[ $operation == init ]]; then
        if [[ -e $reference || -L $reference ]]; then
            log_event ERRO referencia 'motivo=referencia_ja_existe'
            return 2
        fi
        write_reference REFERENCIA_CRIADA
    elif ! read_reference; then
        log_event ERRO referencia 'motivo=referencia_ausente_ou_invalida'
        return 2
    elif ! recover_audit; then
        return 2
    elif [[ $operation == update ]]; then
        write_reference REFERENCIA_ATUALIZADA
    else
        check_reference
    fi
)

if [[ $action != watch ]]; then
    if locked "$action"; then exit 0; else exit "$?"; fi
fi

stop_watch() {
    log_event ENCERRADO monitor 'motivo=sinal' || true
    exit "$1"
}
trap 'stop_watch 130' INT
trap 'stop_watch 143' TERM

overall=0
for (( cycle=1; cycles == 0 || cycle <= cycles; ++cycle )); do
    log_event CICLO monitor "numero=$cycle" || exit 2
    if locked check; then
        result=0
    else
        result=$?
    fi
    if (( result > overall )); then overall=$result; fi
    if (( cycles == 0 || cycle < cycles )); then sleep "$interval"; fi
done
log_event ENCERRADO monitor 'motivo=ciclos_concluidos' || exit 2
exit "$overall"
