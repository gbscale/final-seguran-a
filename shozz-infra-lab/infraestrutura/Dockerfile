
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Pacotes mínimos do roteador. O "apt-get upgrade" aplica as atualizações de
# segurança disponíveis no momento do build.
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    iproute2 \
    iputils-ping \
    openssh-server \
    sudo \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# As chaves de host geradas na instalação do openssh-server são removidas: cada
# contêiner gera as suas na inicialização (hardening/entrypoint.sh).
RUN rm -f /etc/ssh/ssh_host_* && \
    mkdir -p /run/sshd

# Hardening do SSH e chave pública autorizada do usuário "ubuntu".
COPY hardening/ssh/10-shozz-hardening.conf /etc/ssh/sshd_config.d/10-shozz-hardening.conf
COPY hardening/ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys
COPY hardening/entrypoint.sh /usr/local/sbin/shozz-entrypoint.sh

# Permissões dos arquivos sensíveis.
RUN chown root:root /etc/ssh/sshd_config /etc/ssh/sshd_config.d/10-shozz-hardening.conf && \
    chmod 600 /etc/ssh/sshd_config /etc/ssh/sshd_config.d/10-shozz-hardening.conf && \
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh && \
    chmod 700 /home/ubuntu/.ssh && \
    chmod 600 /home/ubuntu/.ssh/authorized_keys && \
    chown root:root /usr/local/sbin/shozz-entrypoint.sh && \
    chmod 755 /usr/local/sbin/shozz-entrypoint.sh

EXPOSE 2222

ENTRYPOINT ["/usr/local/sbin/shozz-entrypoint.sh"]
