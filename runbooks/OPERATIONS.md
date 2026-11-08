# Linux Production Lab — Operations Runbook

## 1. Purpose

This runbook documents routine operational checks and recovery
procedures for the local Linux Production Environment and Incident Lab.

The environment consists of five privileged Docker containers on
the `production-net` bridge network.

| Node | IP address | Primary responsibility |
|---|---|---|
| nginx-01 | 10.10.0.10 | Nginx reverse proxy |
| app-01 | 10.10.0.11 | Application service |
| app-02 | 10.10.0.12 | Application service |
| db-01 | 10.10.0.20 | Linux infrastructure node |
| monitoring-01 | 10.10.0.30 | Prometheus and Grafana |

These are containers running systemd, not independent virtual
machines. Use this runbook for controlled lab operations, not
as a production change-management procedure.

## 2. Routine infrastructure health checks

### Check container state

    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Confirm that all five containers are running.

For a specific container:

    docker inspect -f '{{.State.Status}}' app-01

### Check Docker network

    docker network inspect production-net

Verify that the expected containers are attached to the network
and retain their assigned IP addresses.

### Check resource consumption

    docker stats --no-stream

Review CPU, memory, network I/O, and block I/O for unexpected
resource consumption.

### Check available host disk space

    df -h

Check inode availability as well:

    df -i

Pay attention to the filesystem containing the Docker data root
and the repository's persistent monitoring directories.

## 3. Linux service health checks

### Application nodes

Check the application service:

    docker exec app-01 systemctl is-active production-app
    docker exec app-02 systemctl is-active production-app

Inspect service status when necessary:

    docker exec app-01 systemctl status production-app --no-pager

Inspect recent application service logs:

    docker exec app-01 journalctl -u production-app -n 50 --no-pager

### Nginx

Validate the configuration:

    docker exec nginx-01 nginx -t

Check service state:

    docker exec nginx-01 systemctl is-active nginx

Inspect recent service logs:

    docker exec nginx-01 journalctl -u nginx -n 50 --no-pager

### Monitoring services

Check Prometheus:

    docker exec monitoring-01 systemctl is-active prometheus

Check Grafana:

    docker exec monitoring-01 systemctl is-active grafana-server

Check Node Exporter on an individual node:

    docker exec app-01 systemctl is-active prometheus-node-exporter

Repeat the Node Exporter check on the other monitored nodes when
investigating a missing target.

## 4. Monitoring health checks

### Prometheus targets

Open:

    http://localhost:9090

Navigate to **Status → Targets**.

The `linux_servers` scrape job should contain five targets:

- 10.10.0.10:9100
- 10.10.0.11:9100
- 10.10.0.12:9100
- 10.10.0.20:9100
- 10.10.0.30:9100

The expected healthy state is `UP` for each target.

The configured scrape interval is 15 seconds.

### Grafana

Open:

    http://localhost:3000

Verify that Grafana is accessible, its Prometheus data source is
working, and the configured dashboards return current metrics.

### Node Exporter endpoint

From the monitoring container, inspect a target's metrics endpoint:

    docker exec monitoring-01 curl -fsS http://10.10.0.11:9100/metrics

A successful response contains Prometheus-format metrics.

Change the target IP to inspect another node.

## 5. Application and reverse-proxy checks

Nginx listens on port 80 inside `nginx-01` and forwards requests
to both application nodes on port 8080.

Check application service state first:

    docker exec app-01 systemctl is-active production-app
    docker exec app-02 systemctl is-active production-app

Check the application HTTP endpoint from inside the Docker network:

    docker exec nginx-01 curl -fsS http://10.10.0.11:8080/
    docker exec nginx-01 curl -fsS http://10.10.0.12:8080/

Check Nginx configuration and logs:

    docker exec nginx-01 nginx -t
    docker exec nginx-01 journalctl -u nginx -n 50 --no-pager

Nginx port 80 is not published on the Docker host by the current
Terraform configuration. Do not assume that the reverse proxy is
reachable through the host's localhost address.

## 6. Incident triage procedure

When a service or monitoring target fails, use this sequence:

1. Identify the affected node, service, endpoint, or metric.
2. Check whether the Docker container is running.
3. Check the relevant systemd service state.
4. Inspect recent service logs.
5. Check network attachment and connectivity.
6. Validate configuration before restarting a service.
7. Restore the failed component using the least disruptive action.
8. Verify service recovery and monitoring visibility.
9. Record the cause, corrective action, and validation evidence.

Useful commands:

    docker ps -a
    docker logs --tail 100 app-01
    docker inspect app-01
    docker stats --no-stream
    df -h
    df -i

Do not restart every container as the first response. Isolate the
failure and investigate its likely cause before taking action.

## 7. Service recovery procedures

### Restart an application service

    docker exec app-01 systemctl restart production-app
    docker exec app-01 systemctl is-active production-app

For app-02, replace the container name accordingly.

### Restart Nginx

Validate configuration first:

    docker exec nginx-01 nginx -t

If validation succeeds:

    docker exec nginx-01 systemctl restart nginx
    docker exec nginx-01 systemctl is-active nginx

### Restart Prometheus

    docker exec monitoring-01 systemctl restart prometheus
    docker exec monitoring-01 systemctl is-active prometheus

### Restart Grafana

    docker exec monitoring-01 systemctl restart grafana-server
    docker exec monitoring-01 systemctl is-active grafana-server

### Restart Node Exporter

    docker exec app-01 systemctl restart prometheus-node-exporter
    docker exec app-01 systemctl is-active prometheus-node-exporter

After recovery, return to Prometheus Targets and verify that the
affected target is reporting `UP`.

## 8. Container lifecycle operations

The containers have a Docker restart policy of `unless-stopped`.

To stop an individual lab container:

    docker stop app-01

To start it again:

    docker start app-01

To restart it:

    docker restart app-01

Replace the example container name with the intended node.

A container restart is different from container replacement.
A restart normally retains its writable layer. Recreating or
replacing a container can remove configuration installed inside
that writable layer.

After a container replacement, review the Terraform result,
verify SSH access, and reapply the relevant Ansible playbooks.
Then validate the affected services and monitoring targets.

## 9. Safe lab shutdown and restart

For a temporary shutdown, stop individual containers rather than
destroying the Terraform-managed infrastructure.

Stop the lab containers:

    docker stop nginx-01 app-01 app-02 db-01 monitoring-01

Start them again:

    docker start nginx-01 app-01 app-02 db-01 monitoring-01

Verify the environment after startup:

    docker ps
    docker network inspect production-net

Then check application, Nginx, Prometheus, Grafana, and Node Exporter
services using the checks in this runbook.

The persistent Grafana and Prometheus directories are mounted from
the repository's `data/` directory. Preserve these directories when
you need monitoring history.

Do not run `terraform destroy` for routine shutdown. It removes
Terraform-managed resources and requires deliberate reprovisioning
and configuration afterward.

## 10. Related project documentation

- [Setup Guide](../docs/SETUP.md)
- [Troubleshooting Log](../docs/linux-production-lab-troubleshooting-log.md)
- [Architecture Diagram](../diagrams/architecture.mmd)
- [Incident 001 — Missing Filesystem Metrics](../docs/incidents/INC-001-missing-filesystem-metrics.md)
- [Incident 002 — Monitoring Container Replacement](../docs/incidents/INC-002-monitoring-container-replacement.md)
- [Incident 003 — High CPU on app-01](../docs/incidents/INC-003-high-cpu-app-01.md)
