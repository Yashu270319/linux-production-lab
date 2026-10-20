# Linux Production Environment & Incident Lab

A hands-on Linux infrastructure lab built locally with Docker, Terraform,
Ansible, Prometheus, and Grafana. The project is designed to practise
infrastructure administration, monitoring, troubleshooting, and incident
response without depending on paid cloud resources.

## Architecture

The lab uses a private Docker bridge network with the following nodes:

| Node | Private IP | Role |
|---|---|---|
| nginx-01 | 10.10.0.10 | Web/reverse-proxy node |
| app-01 | 10.10.0.11 | Application and Linux administration |
| app-02 | 10.10.0.12 | Second application node |
| db-01 | 10.10.0.20 | Database-role infrastructure node |
| monitoring-01 | 10.10.0.30 | Prometheus and Grafana |

The topology represents infrastructure roles for learning purposes.
It is not a production cloud deployment, and the database-role node should
not be assumed to run a database service unless separately configured.

## Technology stack

- **Docker:** isolated Linux environments and networking
- **Terraform:** infrastructure provisioning and resource management
- **Ansible:** repeatable operating-system and service configuration
- **Prometheus:** metrics collection and querying
- **Grafana:** dashboards and monitoring visualisation
- **Node Exporter:** Linux host metrics
- **Ubuntu 24.04:** base operating-system image with systemd and administration tools

## Repository layout

```text
.
├── ansible/
│   ├── inventory/
│   ├── playbooks/
│   └── templates/
├── docker/
│   └── server/
├── docs/
│   └── incidents/
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── .terraform.lock.hcl
├── diagrams/
├── incidents/
├── monitoring/
├── runbooks/
└── .gitignore
```

Local monitoring databases, Terraform state, provider binaries, and recovery
archives are intentionally excluded from version control.

## Skills practised

- Linux processes, services, logs, packages, and resource utilisation
- SSH access, users, groups, permissions, and privilege management
- Private networking, IP addressing, ports, and service connectivity
- Infrastructure provisioning with Terraform
- Configuration management with Ansible
- Metrics collection, PromQL investigation, and Grafana dashboards
- Incident investigation, corrective actions, and written runbooks
- Persistent data and recovery considerations for monitoring services

## Incident exercises and investigation notes

Incident reports are maintained under `docs/incidents/`. They record
symptoms, investigation steps, evidence, remediation, and lessons learned.

The current reports include filesystem metrics troubleshooting, a monitoring
container replacement and recovery investigation, and a high-CPU exercise
on app-01.

## Prerequisites

- Linux host
- Docker Engine with permission to manage containers
- Terraform
- Ansible
- Git
- SSH client

Prometheus and Grafana run as part of the local lab setup.

## Important security and portability notes

- Do not commit Terraform state, credentials, private keys, monitoring data,
  database files, or backup archives.
- The SSH public key used by the Docker image is a local input and is excluded
  from this repository. Supply your own authorised public key when building
  the image.
- Review local paths, network availability, and Docker permissions before
  applying Terraform on another machine.
- This project is a local learning environment. It does not by itself provide
  production-grade security, high availability, disaster recovery, or cloud
  infrastructure.

## Current status

The lab has been provisioned locally, configured with Ansible, and extended
with Prometheus/Grafana monitoring. Incident exercises and documentation are
ongoing.

This repository is intended to demonstrate hands-on learning and
troubleshooting evidence, not to claim commercial production experience.
