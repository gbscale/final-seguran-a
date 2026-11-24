
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    iproute2 \
    iputils-ping \
    openssh-server \
    sudo \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd

EXPOSE 2222

CMD ["/usr/sbin/sshd", "-D", "-e"]
