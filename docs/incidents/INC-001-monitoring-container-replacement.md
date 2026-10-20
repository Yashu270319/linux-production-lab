# Incident Report: Monitoring Stack Disruption After Container Replacement

**Incident ID:** INC-001
**Environment:** Local Linux Production Lab
**Severity:** SEV-2 (Lab monitoring outage; no external production impact)
**Status:** Resolved
**Affected component:** `monitoring-01`
**Infrastructure:** Docker, Terraform, Ansible, Prometheus, Grafana, Node Exporter
**Incident date:** 10 October 2026

---

## 1. Executive Summary

The monitoring stack became partially unavailable after Terraform replaced the `monitoring-01` Docker container while applying a configuration change to expose Prometheus on host port `9090`.

The replacement container was created from the base Linux image rather than an image containing the previously installed monitoring applications. Consequently, Prometheus and Grafana were no longer available as installed services inside the replacement container.

The incident exposed a persistence weakness: the monitoring container originally lacked host-mounted volumes for application data. Container replacement could therefore remove software, configuration, and data stored only in the container's writable filesystem.

Recovery involved introducing persistent host-mounted directories, preserving available monitoring data, reinstalling the monitoring applications through Ansible, restoring Node Exporter availability, and verifying Prometheus target health.

**Final outcome:** Prometheus and Grafana were operational again, and Prometheus successfully scraped metrics from all five lab servers.

## 2. Environment Before the Incident

The lab uses a Docker network named `production-net`, with static addresses assigned to its server containers.

| Component | Address | Purpose |
|---|---|---|
| `nginx-01` | `10.10.0.10` | Web server |
| `app-01` | `10.10.0.11` | Application server |
| `app-02` | `10.10.0.12` | Application server |
| `db-01` | `10.10.0.20` | Database server |
| `monitoring-01` | `10.10.0.30` | Prometheus and Grafana |

Node Exporter runs on all five servers and exposes host metrics on port `9100`. Prometheus collects those metrics, while Grafana provides dashboards for visualization.

Infrastructure is managed using Terraform, and software configuration is managed using Ansible.

## 3. Incident Timeline

### Stage 1 — Configuration change

The Prometheus host port mapping was added to the Terraform configuration because port `9090` had not previously been exposed on the host.

Terraform planned to replace `monitoring-01` to apply the updated container configuration.

### Stage 2 — Container replacement

After Terraform applied the change, the replacement container was running, but the previously installed monitoring services were missing.

The key distinction was that Terraform recreated the container from its configured base image. It did not automatically reinstall applications that had previously been installed manually or through Ansible.

### Stage 3 — Initial investigation and data recovery

The investigation established that the monitoring container originally had no persistent host mounts for Grafana and Prometheus data.

Available recovery artifacts were examined:

- A container archive was available at `~/linux-production-lab/backups/monitoring-01-before-port-fix.tar`.
- Prometheus data had been copied into `~/linux-production-lab/backups/prometheus-metrics2`.
- A Grafana SQLite database was recovered and checked for integrity.
- The recovered old Grafana database was structurally valid, but its dashboard, dashboard-version, dashboard-snapshot, and folder tables contained no user records.

Therefore, the old Grafana dashboards could not be recovered from that database. The old database was not restored over the current database.

### Stage 4 — Persistent storage correction

Host-mounted data directories were introduced into the Terraform configuration:

- `~/linux-production-lab/data/grafana` → `/var/lib/grafana`
- `~/linux-production-lab/data/prometheus` → `/var/lib/prometheus/metrics2`

Available Grafana and Prometheus data was copied to the host directories, and ownership was set for the respective service accounts.

Terraform validation succeeded, and the monitoring container was replaced with the volume mappings configured.

The software still needed to be reinstalled because the replacement container originated from the base image.

### Stage 5 — Service recovery

Prometheus was restored using the Ansible playbook `playbooks/prometheus.yml`.

Grafana was restored using `playbooks/grafana.yml`.

Node Exporter was restored and verified using `playbooks/node-exporter.yml`. SSH access to `monitoring-01` also had to be verified, and the explicit private-key argument was used for root-run Ansible commands.

### Stage 6 — Final verification

All five Node Exporter services reported `active`.

Prometheus's `/api/v1/targets` endpoint reported all five targets as `up`, with empty scrape errors.

Grafana's service and HTTP health endpoint were subsequently checked and confirmed operational.

## 4. Symptoms and Findings

| Symptom | Finding |
|---|---|
| Grafana service was unavailable | `grafana-server` was not installed in the replacement container. |
| Prometheus was initially unavailable | Prometheus also needed to be restored inside the replacement container. |
| Ansible initially reported SSH authentication failure | Explicitly selecting `~/.ssh/id_ed25519` enabled successful authentication. |
| Node Exporter was initially down on `monitoring-01` | The service was restored and verified active. |
| All five Prometheus targets eventually became healthy | Prometheus could reach each Node Exporter endpoint on port `9100`. |
| Old Grafana dashboards were not restored | The recovered old database contained no user dashboard records in the inspected tables. |
| Replacing the container risked losing monitoring data | The original container definition did not have the required persistent mounts. |

## 5. Root Cause Analysis

### Primary root cause

**The monitoring container's lifecycle was coupled to application installation and data stored inside the container.**

Terraform was responsible for container infrastructure, but the container definition did not originally provide persistent host-mounted storage for the monitoring applications' data. Replacing the container therefore removed the previous container's writable filesystem, including installed software and other non-persistent state.

### Contributing factors

1. The container was created from a base image that did not contain Grafana and Prometheus installations.
2. Persistent volume mappings were missing from the original monitoring container configuration.
3. The container replacement required the monitoring services to be reinstalled.
4. The recovered Grafana database did not contain the old user dashboards, preventing their restoration from that artifact.
5. Root-run Ansible needed an explicit SSH private-key argument to authenticate successfully.

### What was not established

The investigation did not establish a separate application-level fault in Grafana or Prometheus. Their initial unavailability was associated with the container replacement and missing installations.

The investigation also did not establish that every item of the original Grafana state was recoverable from the available archive.

## 6. Recovery Actions

- [x] Verified the replacement container and its service state.
- [x] Inspected available monitoring backups.
- [x] Checked the recovered Grafana database's integrity and dashboard-related tables.
- [x] Added host-mounted volumes for Grafana and Prometheus data.
- [x] Restored available data into the persistent host directories.
- [x] Corrected service-data ownership.
- [x] Reinstalled Prometheus through Ansible.
- [x] Reinstalled Grafana through Ansible.
- [x] Restored Node Exporter across all five servers.
- [x] Verified Prometheus readiness and target health.
- [x] Verified Grafana's service and HTTP health endpoint.

## 7. Final Verification Evidence

### Node Exporter services

Command executed:

```bash
sudo ansible linux_servers \
  -i inventory/hosts.ini \
  -m shell \
  -a 'systemctl is-active prometheus-node-exporter' \
  --private-key=~/.ssh/id_ed25519 \
  -f 1
```

Result: all five hosts returned `active`.

### Prometheus target health

Endpoint checked:

```bash
curl -s http://localhost:9090/api/v1/targets
```

Observed results:

| Target | Health | Last error |
|---|---|---|
| `10.10.0.10:9100` | `up` | None |
| `10.10.0.11:9100` | `up` | None |
| `10.10.0.12:9100` | `up` | None |
| `10.10.0.20:9100` | `up` | None |
| `10.10.0.30:9100` | `up` | None |

Prometheus reported five active targets with no scrape errors.

### Grafana

- Ansible playbook completed with `failed=0` and `unreachable=0`.
- The Grafana service was confirmed active.
- The Grafana health endpoint returned a healthy database response.

## 8. Corrective and Preventive Actions

### Completed

1. Added persistent host-mounted storage for Grafana and Prometheus data.
2. Recovered available monitoring data into those host directories.
3. Restored monitoring services through repeatable Ansible playbooks.
4. Verified service status and Prometheus scrape health.

### Recommended next actions

1. **Keep application data outside replaceable containers.** Continue using host-mounted volumes for stateful monitoring data.
2. **Make the monitoring stack reproducible.** Ensure a new monitoring container can be configured through Ansible without relying on manual installation.
3. **Back up Grafana dashboards separately.** Export dashboard definitions as JSON and store them under version control.
4. **Back up monitoring data regularly.** Document the appropriate backup and recovery procedure for Prometheus data and Grafana's database.
5. **Test container replacement deliberately.** Verify that persistent data survives a planned replacement before relying on the configuration.
6. **Improve change safety.** Review Terraform plans before applying changes to stateful services, and check whether replacement will affect application availability.
7. **Document verification commands.** Keep a runbook for service health, Prometheus target status, and Grafana API health.

## 9. Lessons Learned

### Container infrastructure is not application configuration

Terraform can create the required container, network, port mappings, and volumes. It does not automatically recreate packages or application configuration unless those are built into the image or provisioned separately.

### Persistent volumes protect data, not software installations

A host-mounted volume preserves data stored in the mounted directory. It does not preserve Grafana or Prometheus binaries, systemd unit files, package installations, or unrelated configuration stored elsewhere in the container.

### Configuration management enables recovery

Ansible made it possible to reinstall and configure the monitoring applications consistently after the container replacement.

### Monitoring requires monitoring the monitoring system

Prometheus and Grafana are themselves infrastructure services. Their availability, persistent storage, and recovery process must be included in the lab's operational design.

## 10. Closure

**Incident status: Resolved.**

The monitoring stack has been restored, and all five Prometheus targets are healthy. Grafana is responding again.

The principal infrastructure improvement is the addition of persistent host-mounted data directories for Grafana and Prometheus. The incident also identified the need for separately backed-up Grafana dashboard definitions and a tested recovery runbook.

**Outstanding follow-up:** Recreate and verify the Grafana dashboards, confirm the Prometheus data source, and test the persistence configuration during a controlled future container replacement.
