# Setup Guide

## 1. Overview

This guide describes how to deploy the Linux Production Environment
and Incident Lab on a Linux host.

The environment uses:

- Docker Engine for Linux containers and networking
- Terraform for infrastructure provisioning
- Ansible for Linux and service configuration
- Nginx for reverse proxying
- Prometheus and Node Exporter for metrics collection
- Grafana for monitoring dashboards

This is a local engineering lab, not a hardened production deployment.
It uses privileged Docker containers running systemd rather than
independent virtual machines.

Follow this guide on a fresh host or a deliberately clean lab.
If an environment already exists, inspect its Terraform state and plan
before applying changes.

## 2. Prerequisites

Install and verify the following tools:

- Docker Engine
- Terraform
- Ansible
- Git
- OpenSSH client

Check that Docker is running and that your account can access it:

    docker ps

Do not use sudo with Terraform merely to bypass Docker permission
problems. Resolve Docker access before continuing.

## 3. Clone the repository

    git clone https://github.com/Yashu270319/linux-production-lab.git
    cd linux-production-lab

Run the remaining commands from the repository root unless stated
otherwise.

## 4. Prepare the SSH key

The Docker image expects a public key at:

    docker/server/authorized_keys

This file is intentionally excluded from Git. Copy your own public
key into it. For example:

    mkdir -p ~/.ssh
    cp ~/.ssh/id_ed25519.pub docker/server/authorized_keys
    chmod 600 docker/server/authorized_keys

If you do not already have an SSH key, generate one first:

    ssh-keygen -t ed25519

Never copy your private key into the repository.

## 5. Build the Linux server image

From the repository root:

    docker build -t linux-production-server:1.3 ./docker/server

Verify that the image exists:

    docker image ls linux-production-server

## 6. Provision infrastructure with Terraform

Enter the Terraform directory:

    cd terraform

Initialize and validate the configuration:

    terraform init
    terraform validate

Review the proposed infrastructure changes:

    terraform plan

Only apply after reviewing the plan:

    terraform apply

Return to the repository root:

    cd ..

Terraform state is stored locally. Do not commit state files,
state backups, or the local .terraform directory.

## 7. Configure the Linux nodes with Ansible

First verify SSH connectivity to all inventory hosts:

    ansible -i ansible/inventory/hosts.ini linux_servers \
      -m ping \
      --private-key ~/.ssh/id_ed25519

Each reachable host should return `pong`.

Run the playbooks from the repository root, in this order:

### Base Linux configuration

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/base.yml --private-key ~/.ssh/id_ed25519

### Application services

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/app.yml --private-key ~/.ssh/id_ed25519

### Nginx reverse proxy

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/nginx.yml --private-key ~/.ssh/id_ed25519

### Node Exporter

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/node-exporter.yml --private-key ~/.ssh/id_ed25519

### Prometheus

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/prometheus.yml --private-key ~/.ssh/id_ed25519

### Grafana

    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/grafana.yml --private-key ~/.ssh/id_ed25519

If your private key is stored elsewhere, replace the example path.
SSH connectivity must work before Ansible can configure the nodes.

## 8. Verify the deployment

### Check Docker infrastructure

    docker ps

Confirm that the five lab containers are running.

Inspect the Docker network:

    docker network inspect production-net

The expected network subnet is `10.10.0.0/24`.

### Check Ansible connectivity

    ansible -i ansible/inventory/hosts.ini linux_servers \
      -m ping \
      --private-key ~/.ssh/id_ed25519

### Check Linux services

Check the application service on an application node:

    docker exec app-01 systemctl is-active production-app

Check Nginx:

    docker exec nginx-01 nginx -t
    docker exec nginx-01 systemctl is-active nginx

### Check monitoring interfaces

The Terraform configuration publishes these monitoring ports on
the Docker host:

- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

Open Prometheus and inspect **Status → Targets** to check scrape
target health.

Open Grafana and verify that its data source and dashboards are
configured and returning metrics.

### Understand Nginx access

Nginx listens on port 80 inside `nginx-01`. The inspected Terraform
configuration does not publish that port on the host. Its reverse
proxy and application checks should therefore be performed from
within the Docker network or a lab container, rather than assuming
that `http://localhost` on the host reaches Nginx.

## 9. Lifecycle and data considerations

This lab uses Docker containers running systemd. Configuration
installed inside a container's writable layer can be lost if that
container is replaced.

Before applying Terraform changes to an existing environment:

1. Review the Terraform plan.
2. Identify resources that Terraform proposes to replace or destroy.
3. Consider which services and configurations would need to be
   reapplied with Ansible.
4. Back up any important configuration or data before proceeding.

Grafana and Prometheus data directories are mounted from the host
under the repository's `data/` directory. Keep these directories
out of Git and preserve them when you need monitoring history.

Do not use `terraform destroy` as a routine shutdown command.
Understand its impact on containers, network resources, and data
before using it.

## 10. Repository hygiene

Do not commit:

- Terraform state or state backups
- The `.terraform/` working directory
- SSH private keys or `authorized_keys`
- Environment files containing secrets
- Monitoring data, backups, or generated runtime files

Keep `.terraform.lock.hcl` under version control so the selected
Terraform provider versions remain reproducible.

## 11. Lab limitations

- The nodes are privileged Docker containers, not independent VMs.
- `db-01` is a Linux infrastructure node; no database service is
  configured.
- The Docker subnet `10.10.0.0/24` must not conflict with existing
  networks.
- The lab is intended for local learning and controlled experiments,
  not direct production use.
- Review security, resource limits, network exposure, and persistence
  before adapting the environment for other purposes.
