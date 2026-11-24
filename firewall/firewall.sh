#!/usr/bin/env bash
# Firewall IPv4 do roteador Shozz. Executar no namespace do contêiner.
set -euo pipefail
umask 077

readonly LAN_NET=10.10.10.0/24 WAN_NET=10.20.20.0/24
readonly LAN_ROUTER=10.10.10.1 WAN_ROUTER=10.20.20.1
readonly LAN_CLIENT=10.10.10.10 WAN_CLIENT=10.20.20.10 LAN_GATEWAY=10.10.10.254
readonly STATE_DIR=/run/shozz-firewall
readonly BASELINE=$STATE_DIR/filter-before.rules

fail() {
    printf 'shozz-firewall: %s\n' "$*" >&2
    exit 1
}

require_router() {
    [[ -f /.dockerenv && $(hostname) == ubuntu-router && $EUID -eq 0 ]] ||
        fail 'Execute como root no contêiner Docker ubuntu-router.'

    # A ordem de conexão às bridges pode trocar eth0 e eth1.
    local addresses
    addresses=$(ip -o -4 address show)
    lan_if=$(awk -v addr="$LAN_ROUTER/24" '$4 == addr { split($2, name, "@"); print name[1] }' <<< "$addresses")
    wan_if=$(awk -v addr="$WAN_ROUTER/24" '$4 == addr { split($2, name, "@"); print name[1] }' <<< "$addresses")
    [[ $lan_if =~ ^[a-zA-Z0-9_.-]+$ && $wan_if =~ ^[a-zA-Z0-9_.-]+$ && $lan_if != "$wan_if" ]] ||
        fail 'As duas interfaces IPv4 esperadas não foram encontradas.'
}

render_rules() {
    # A tabela filter é carregada em uma única transação. NAT e outras tabelas
    # ficam fora dela. OUTPUT permite respostas e tráfego originado no roteador.
    cat <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:SHOZZ_SSH - [0:0]
:SHOZZ_SSH_RATE - [0:0]
:SHOZZ_INPUT_DENY - [0:0]
:SHOZZ_FORWARD_DENY - [0:0]

# Loopback, descarte de estados inválidos e validação de origem por interface.
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -i $lan_if ! -s $LAN_NET -j SHOZZ_INPUT_DENY
-A INPUT -i $wan_if ! -s $WAN_NET -j SHOZZ_INPUT_DENY

# SSH só entra pela LAN com destino ao endereço administrativo da LAN.
# Checar antes da regra geral de estado também bloqueia sessões SSH antigas da WAN.
-A INPUT -p tcp --dport 2222 -j SHOZZ_SSH

# Processar todo echo-request antes de ESTABLISHED limita também pings com ID repetido.
-A INPUT -i $lan_if -s $LAN_CLIENT/32 -d $LAN_ROUTER/32 -p icmp --icmp-type echo-request -m hashlimit --hashlimit-upto 3/sec --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name shozz_icmp_in -j ACCEPT
-A INPUT -p icmp --icmp-type echo-request -j SHOZZ_INPUT_DENY
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -j SHOZZ_INPUT_DENY

# Encaminhar diagnóstico LAN para WAN e o retorno. As bridges e rotas são do Compose.
-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -i $lan_if ! -s $LAN_NET -j SHOZZ_FORWARD_DENY
-A FORWARD -i $wan_if ! -s $WAN_NET -j SHOZZ_FORWARD_DENY
-A FORWARD -i $lan_if -o $wan_if -s $LAN_CLIENT/32 -d $WAN_CLIENT/32 -p icmp --icmp-type echo-request -m hashlimit --hashlimit-upto 3/sec --hashlimit-burst 5 --hashlimit-mode srcip --hashlimit-name shozz_icmp_fwd -j ACCEPT
-A FORWARD -p icmp --icmp-type echo-request -j SHOZZ_FORWARD_DENY
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -j SHOZZ_FORWARD_DENY

# Mesmo conjunto de origens para sessões administrativamente permitidas.
-A SHOZZ_SSH ! -i $lan_if -j SHOZZ_INPUT_DENY
-A SHOZZ_SSH ! -d $LAN_ROUTER/32 -j SHOZZ_INPUT_DENY
-A SHOZZ_SSH -s $LAN_CLIENT/32 -m conntrack --ctstate ESTABLISHED -j ACCEPT
-A SHOZZ_SSH -s $LAN_GATEWAY/32 -m conntrack --ctstate ESTABLISHED -j ACCEPT
-A SHOZZ_SSH -s $LAN_CLIENT/32 -p tcp --syn -m conntrack --ctstate NEW -j SHOZZ_SSH_RATE
-A SHOZZ_SSH -s $LAN_GATEWAY/32 -p tcp --syn -m conntrack --ctstate NEW -j SHOZZ_SSH_RATE
-A SHOZZ_SSH -j SHOZZ_INPUT_DENY

# Cada IP autorizado tem 4 créditos iniciais e repõe 1 a cada 5 segundos em média.
-A SHOZZ_SSH_RATE -m hashlimit --hashlimit-upto 12/min --hashlimit-burst 4 --hashlimit-mode srcip --hashlimit-name shozz_ssh_new -j ACCEPT
-A SHOZZ_SSH_RATE -m limit --limit 4/min --limit-burst 4 -j LOG --log-prefix "shozz ssh rate " --log-level 6
-A SHOZZ_SSH_RATE -j DROP

# O limite afeta só a escrita do log. Todo pacote que chega aqui é descartado.
-A SHOZZ_INPUT_DENY -m limit --limit 4/min --limit-burst 4 -j LOG --log-prefix "shozz input drop " --log-level 6
-A SHOZZ_INPUT_DENY -j DROP
-A SHOZZ_FORWARD_DENY -m limit --limit 4/min --limit-burst 4 -j LOG --log-prefix "shozz forward drop " --log-level 6
-A SHOZZ_FORWARD_DENY -j DROP
COMMIT
EOF
}

save_filter() {
    local policies
    policies=$(iptables -w 5 -S)
    iptables-save -c -t filter > "$1"

    # Um namespace novo pode ainda não ter uma tabela filter materializada.
    if ! grep -qx '\*filter' "$1"; then
        [[ $policies == $'-P INPUT ACCEPT\n-P FORWARD ACCEPT\n-P OUTPUT ACCEPT' ]] ||
            fail 'O backup da tabela filter saiu vazio apesar de existirem regras.'
        printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$1"
    fi
}

install_filter() {
    local next=$1 previous=$2
    iptables-restore -w 5 -c --test < "$next" || fail 'Validação das regras falhou.'
    if ! iptables-restore -w 5 -c < "$next"; then
        iptables-restore -w 5 -c < "$previous" || fail 'Falha ao aplicar e ao recuperar o filtro anterior.'
        fail 'Falha ao aplicar. O filtro anterior foi restaurado.'
    fi
}

case ${1:-} in
    start)
        shift
        case ${SHOZZ_FIREWALL:-on} in
            on) "$0" apply ;;
            off) printf 'shozz-firewall: aplicação desativada para esta inicialização.\n' ;;
            *) fail 'SHOZZ_FIREWALL deve ser on ou off.' ;;
        esac
        exec /usr/local/sbin/shozz-entrypoint.sh "$@"
        ;;
    apply|restore|status)
        [[ $# -eq 1 ]] || fail 'Uso: shozz-firewall {apply|restore|status}'
        ;;
    *) fail 'Uso: shozz-firewall {apply|restore|status}' ;;
esac

require_router
if [[ $1 == status ]]; then
    iptables -w 5 -vnL --line-numbers
    exit
fi

# Serializar apply/restore e criar um backup protegido antes de qualquer DROP.
install -d -m 0700 "$STATE_DIR"
exec 9> "$STATE_DIR/lock"
flock -w 5 9 || fail 'Outra operação de firewall está em curso.'
work_dir=$(mktemp -d "$STATE_DIR/work.XXXXXXXX")
trap 'rm -f "$work_dir/current.rules" "$work_dir/next.rules"; rmdir "$work_dir"' EXIT
save_filter "$work_dir/current.rules"
iptables-restore -w 5 -c --test < "$work_dir/current.rules" || fail 'O backup atual não é restaurável.'

if [[ $1 == restore ]]; then
    [[ -s $BASELINE ]] || fail 'Não há backup da primeira aplicação neste contêiner.'
    install_filter "$BASELINE" "$work_dir/current.rules"
    printf 'shozz-firewall: tabela filter original restaurada.\n'
else
    if [[ ! -e $BASELINE ]]; then
        cp "$work_dir/current.rules" "$work_dir/next.rules"
        mv "$work_dir/next.rules" "$BASELINE"
    fi
    render_rules > "$work_dir/next.rules"
    install_filter "$work_dir/next.rules" "$work_dir/current.rules"
    printf 'shozz-firewall: ativo (LAN=%s, WAN=%s). Backup: %s\n' "$lan_if" "$wan_if" "$BASELINE"
fi
