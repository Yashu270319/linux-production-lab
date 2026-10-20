# Setup Guide

This is a local Linux infrastructure lab built with Docker, Terraform,
Ansible, Prometheus, and Grafana. It is intended for learning, not as
a hardened production deployment.

These instructions assume a fresh machine or a deliberately clean lab.
Do not apply Terraform changes to an existing environment without
reviewing the plan.

## Prerequisites

Install Docker Engine, Terraform, Ansible, Git, and the OpenSSH client.
Verify Docker access by running `docker ps`. Resolve Docker permissions
before continuing; avoid running Terraform with sudo just to bypass them.

## Clone the repository

Run `git clone https://github.com/Yashu270319/linux-production-lab.git`
and then `cd linux-production-lab`.

## Prepare the SSH key

The Docker image expects `docker/server/authorized_keys`, which is
intentionally excluded from Git. Copy your own public SSH key into that
file. For example, use `cp ~/.ssh/id_ed25519.pub docker/server/authorized_keys`.
Never copy a private key into the repository.

## Build the server image

From the repository root, run:
`docker build -t linux-production-server:1.3 ./docker/server`

## Provision with Terraform

Enter `terraform/`, then run `terraform init`, `terraform validate`,
and `terraform plan`. Review the plan before running `terraform apply`.
Return to the repository root afterward.

Terraform state is local and must not be committed.

## Configure with Ansible

Use the inventory at `ansible/inventory/hosts.ini`. The playbooks are
under `ansible/playbooks/`. Run `base.yml` first, followed by `app.yml`,
`nginx.yml`, `node-exporter.yml`, `prometheus.yml`, and `grafana.yml`.
Pass the private key matching your supplied public key using
`--private-key ~/.ssh/id_ed25519`; adjust the path if needed.

SSH connectivity must work before Ansible can configure the nodes.

## Verify

Check containers with `docker ps`. Test Ansible connectivity with:
`ansible -i ansible/inventory/hosts.ini linux_servers -m ping --private-key ~/.ssh/id_ed25519`

After monitoring setup, Grafana is expected at `http://localhost:3000`
and Prometheus at `http://localhost:9090`.

## Limitations

- The lab uses privileged Linux containers, not independent virtual machines.
- `db-01` is a Linux infrastructure node; no database service is configured.
- The Docker subnet `10.10.0.0/24` must be available.
- Keep Terraform state, monitoring data, credentials, and private keys out of Git.
- Review security, resource limits, network exposure, and persistence before adapting this lab.
