FROM ubuntu:24.04

# Suppress interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    bc \
    procps \
    iproute2 \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# sshd needs this directory to exist
RUN mkdir -p /run/sshd

# Create a non-root test user
RUN useradd -m -s /bin/bash orbital && \
    echo 'orbital:orbital' | chpasswd

# Harden sshd config while keeping it useful for dev
RUN sed -i \
    -e 's/#PasswordAuthentication yes/PasswordAuthentication yes/' \
    -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
    -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
    /etc/ssh/sshd_config

# Port 22 inside the container — mapped to 2222 on the host via compose
EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
