FROM ubuntu:24.04

ENV container=docker

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    systemd \
    systemd-sysv \
    openssh-server \
    sudo \
    iproute2 \
    iputils-ping \
    curl \
    vim \
    nano \
    procps \
    net-tools \
    dnsutils \
    cron \
    locales \
    rsyslog \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

RUN useradd -m -s /bin/bash ops && \
    usermod -aG sudo ops && \
    echo "ops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ops && \
    chmod 440 /etc/sudoers.d/ops && \
    mkdir -p /home/ops/.ssh && \
    chown -R ops:ops /home/ops/.ssh && \
    chmod 700 /home/ops/.ssh

COPY authorized_keys /home/ops/.ssh/authorized_keys

RUN chown ops:ops /home/ops/.ssh/authorized_keys && \
    chmod 600 /home/ops/.ssh/authorized_keys

RUN mkdir -p /run/sshd && \
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
