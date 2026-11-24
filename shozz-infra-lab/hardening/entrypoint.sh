#!/bin/sh
# Ponto de entrada do roteador Ubuntu (Shozz Infra Lab).
set -eu

# As chaves de host do SSH não são distribuídas na imagem: são geradas aqui,
# uma vez por contêiner. Se já existirem (reinício do mesmo contêiner), são mantidas.
ssh-keygen -A

# Não inicia o serviço com uma configuração inválida.
/usr/sbin/sshd -t

# sshd em primeiro plano (PID 1), com log na saída padrão (docker logs).
exec /usr/sbin/sshd -D -e "$@"
