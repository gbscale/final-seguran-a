#!/usr/bin/env bash
set -euo pipefail
umask 077
export LC_ALL=C

if [[ $# != 1 || -e $1 || -L $1 ]]; then
    printf 'Uso: bash demo-gpg.sh DIRETORIO_NOVO_DE_EXPORTACAO\n' >&2
    exit 2
fi

output=$1
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config="$source_dir/exemplos/config-isp-demo.ini"
work_dir=$(mktemp -d /tmp/isp-gpg-demo.XXXXXXXX)
alice_home="$work_dir/alice"
bruno_home="$work_dir/bruno"
audit_home="$work_dir/auditoria"
transfer="$work_dir/transferencia"
cleanup() {
    local home
    for home in "$alice_home" "$bruno_home" "$audit_home"; do
        gpgconf --homedir "$home" --kill all >/dev/null 2>&1 || true
    done
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -m 700 -- "$alice_home" "$bruno_home" "$audit_home" "$transfer"

trace() {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
}

run() {
    trace "$@"
    "$@"
}

key_fingerprint() {
    awk -F: '$1 == "fpr" && !primary++ { print $10 }'
}

generate() {
    local -n keyring=$1
    local uid=$2 fingerprint
    run "${keyring[@]}" --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$uid" ed25519 cert,sign 30d >&2
    trace "${keyring[@]}" --with-colons --fingerprint "$uid" >&2
    fingerprint=$("${keyring[@]}" --with-colons --fingerprint "$uid" | key_fingerprint)
    [[ $fingerprint =~ ^[A-F0-9]{40}$ ]] || return 1
    run "${keyring[@]}" --pinentry-mode loopback --passphrase '' \
        --quick-add-key "$fingerprint" cv25519 encr 30d >&2
    printf '%s\n' "$fingerprint"
}

confirm_export() {
    local -n receiver=$1
    local file=$2 expected=$3 metadata
    trace "${receiver[@]}" --with-colons --show-keys "$file"
    metadata=$("${receiver[@]}" --with-colons --show-keys "$file") || return 1
    if ! awk -F: -v expected="$expected" '
        $1 == "pub" { ++keys; primary=1 }
        $1 == "sec" || $1 == "ssb" { secret=1; primary=0 }
        $1 == "sub" { primary=0 }
        $1 == "fpr" && primary { if ($10 == expected) ++matches; primary=0 }
        END { exit !(keys == 1 && matches == 1 && !secret) }
    ' <<< "$metadata"; then
        printf 'Importacao recusada: o arquivo deve conter apenas a chave publica com o fingerprint esperado.\n' >&2
        return 1
    fi
    printf 'Fingerprint conferido pelo canal independente simulado: %s\n' "$expected"
    run "${receiver[@]}" --import "$file"
}

confirm_certification() {
    local subject=$1 signer=$2 result
    trace "${audit[@]}" --with-colons --check-sigs "$subject"
    result=$("${audit[@]}" --with-colons --check-sigs "$subject")
    awk -F: -v keyid="${signer: -16}" '$1 == "sig" && $2 == "!" && $5 == keyid { valid=1 } END { exit !valid }' <<< "$result"
    printf 'Certificacao de %s por %s verificada no chaveiro publico\n' "$subject" "$signer"
}

alice=(gpg --no-options --homedir "$alice_home" --batch --no-tty)
bruno=(gpg --no-options --homedir "$bruno_home" --batch --no-tty)
audit=(gpg --no-options --homedir "$audit_home" --batch --no-tty)
alice_uid='Alice NOC (ISP laboratorio) <alice@isp.example.invalid>'
bruno_uid='Bruno NOC (ISP laboratorio) <bruno@isp.example.invalid>'

printf 'Inicio UTC: %s\n' "$(date -u +%FT%TZ)"
run "${alice[@]}" --version
alice_fpr=$(generate alice "$alice_uid")
bruno_fpr=$(generate bruno "$bruno_uid")
printf 'Fingerprint original de Alice: %s\nFingerprint original de Bruno: %s\n' "$alice_fpr" "$bruno_fpr"

run "${alice[@]}" --armor --output "$work_dir/alice-inicial.asc" --export "$alice_fpr"
run "${bruno[@]}" --armor --output "$work_dir/bruno-inicial.asc" --export "$bruno_fpr"

printf '\nRegressao de importacao com os chaveiros de demonstracao\n'
# O arquivo testado contém duas chaves públicas, a esperada vem primeiro.
trace cat -- "$work_dir/alice-inicial.asc" "$work_dir/bruno-inicial.asc"
cat -- "$work_dir/alice-inicial.asc" "$work_dir/bruno-inicial.asc" > "$work_dir/chaves-extras.asc"
bundle_keys=$("${audit[@]}" --with-colons --show-keys "$work_dir/chaves-extras.asc")
if [[ $(awk -F: '$1 == "pub" { ++keys } END { print keys+0 }' <<< "$bundle_keys") != 2 ]]; then
    printf 'ERRO: a amostra da regressao nao tem duas chaves publicas validas.\n' >&2
    exit 1
fi
if confirm_export audit "$work_dir/chaves-extras.asc" "$alice_fpr"; then
    printf 'ERRO: arquivo com chave extra foi aceito.\n' >&2
    exit 1
fi
if confirm_export audit "$work_dir/bruno-inicial.asc" "$alice_fpr"; then
    printf 'ERRO: arquivo com fingerprint incorreto foi aceito.\n' >&2
    exit 1
fi
audit_keys=$("${audit[@]}" --with-colons --list-keys)
if grep -q '^pub:' <<< "$audit_keys"; then
    printf 'ERRO: o chaveiro foi alterado por uma importacao recusada.\n' >&2
    exit 1
fi
printf 'Regressao GPG: chave extra e fingerprint incorreto rejeitados; chaveiro intacto.\n'

confirm_export alice "$work_dir/bruno-inicial.asc" "$bruno_fpr"
confirm_export bruno "$work_dir/alice-inicial.asc" "$alice_fpr"

run "${alice[@]}" --yes --pinentry-mode loopback --passphrase '' --quick-sign-key "$bruno_fpr"
run "${bruno[@]}" --yes --pinentry-mode loopback --passphrase '' --quick-sign-key "$alice_fpr"
run "${bruno[@]}" --armor --output "$transfer/alice-publica.asc" --export "$alice_fpr"
run "${alice[@]}" --armor --output "$transfer/bruno-publica.asc" --export "$bruno_fpr"
confirm_export audit "$transfer/alice-publica.asc" "$alice_fpr"
confirm_export audit "$transfer/bruno-publica.asc" "$bruno_fpr"
confirm_certification "$alice_fpr" "$bruno_fpr"
confirm_certification "$bruno_fpr" "$alice_fpr"

run "${alice[@]}" --pinentry-mode loopback --passphrase '' --armor --local-user "$alice_fpr" \
    --output "$transfer/config-isp-demo.sig.asc" --detach-sign "$config"
run "${alice[@]}" --pinentry-mode loopback --passphrase '' --armor --local-user "$alice_fpr" \
    --recipient "$bruno_fpr" --output "$transfer/config-isp-demo.cifrado.asc" --sign --encrypt "$config"

printf '\nTransferencia simulada de Alice para Bruno\n'
run cp -- "$transfer/config-isp-demo.cifrado.asc" "$bruno_home/"
decrypt=("${bruno[@]}" --pinentry-mode loopback --passphrase '' --status-fd 1
    --output "$work_dir/recuperado.ini" --decrypt "$bruno_home/config-isp-demo.cifrado.asc")
trace "${decrypt[@]}"
verified=$("${decrypt[@]}")
grep -F "[GNUPG:] VALIDSIG $alice_fpr " <<< "$verified"
grep -Fx '[GNUPG:] DECRYPTION_OKAY' <<< "$verified"
run "${bruno[@]}" --verify "$transfer/config-isp-demo.sig.asc" "$work_dir/recuperado.ini"
run cmp -- "$config" "$work_dir/recuperado.ini"
run sha256sum -- "$config" "$work_dir/recuperado.ini"
printf 'Conteudo recuperado identico ao original\n'

trace "${alice[@]}" --status-fd 1 --output "$work_dir/indevido.ini" --decrypt "$transfer/config-isp-demo.cifrado.asc"
if wrong_key=$("${alice[@]}" --status-fd 1 --output "$work_dir/indevido.ini" --decrypt "$transfer/config-isp-demo.cifrado.asc"); then
    printf 'ERRO: uma chave nao destinataria conseguiu descriptografar\n' >&2
    exit 1
fi
grep -F '[GNUPG:] NO_SECKEY ' <<< "$wrong_key"

run cp -- "$work_dir/recuperado.ini" "$work_dir/adulterado.ini"
printf '\n; alteracao controlada\n' >> "$work_dir/adulterado.ini"
trace "${bruno[@]}" --status-fd 1 --verify "$transfer/config-isp-demo.sig.asc" "$work_dir/adulterado.ini"
if changed=$("${bruno[@]}" --status-fd 1 --verify "$transfer/config-isp-demo.sig.asc" "$work_dir/adulterado.ini"); then
    printf 'ERRO: assinatura aceitou conteudo diferente\n' >&2
    exit 1
fi
grep -F '[GNUPG:] BADSIG ' <<< "$changed"

run mkdir -- "$output"
run cp -- "$transfer/alice-publica.asc" "$transfer/bruno-publica.asc" \
    "$transfer/config-isp-demo.cifrado.asc" "$transfer/config-isp-demo.sig.asc" "$output/"
printf 'DEMONSTRACAO GPG CONCLUIDA\n'
