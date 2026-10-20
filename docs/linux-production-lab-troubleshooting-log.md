# Linux Production Lab — Troubleshooting and Lessons Learned

**Document type:** Project troubleshooting log
**Environment:** Local Docker-based Linux production lab
**Scope:** Terraform, Docker, Linux/systemd, SSH, Ansible, Prometheus, Node Exporter, Grafana, networking
**Purpose:** Record real issues encountered, the evidence used to diagnose them, fixes applied, and how the same class of problem should be handled in production.

> This is a project log, not a claim that the lab is equivalent to a production fleet. Several exercises were performed in containers. The lessons about diagnostics, configuration management, observability, and recovery transfer to production; container-specific behavior must be interpreted carefully.

## Quick index

| ID | Problem | Status |
|---|---|---|
| LAB-001 | Docker socket permission denied | Resolved |
| LAB-002 | Terraform provider/state inconsistency and containers with missing IPs | Recovered; exact underlying cause not conclusively established |
| LAB-003 | Docker network subnet overlap | Resolved by choosing a non-overlapping lab subnet |
| LAB-004 | Nginx upstream could not resolve backend names | Resolved by aligning backend addressing/configuration |
| LAB-005 | Requests repeatedly reached the same backend | Resolved by correcting backend response/configuration |
| LAB-006 | Container did not have systemd available as expected | Resolved by building a systemd-capable custom image |
| LAB-007 | Ansible failed due to non-UTF-8 locale | Resolved by fixing system locale |
| LAB-008 | PC reboot left the lab unavailable / containers exited | Resolved with restart policies and recovery/reconfiguration |
| LAB-009 | Recreated containers lost Ansible-installed configuration | Recovered by rerunning configuration playbooks |
| LAB-010 | SSH host-key warnings after container recreation | Addressed by removing stale known-host entries and reconnecting |
| LAB-011 | Node Exporter flag unsupported; service failed | Resolved by using flags supported by the installed binary |
| LAB-012 | Root filesystem metrics missing from Grafana | Resolved by adjusting Node Exporter's filesystem exclusion filter |
| LAB-013 | Grafana was not reachable externally from the host | Resolved by publishing container port 3000 |
| LAB-014 | Grafana listening address was misread as a port issue | Resolved by checking socket listeners and HTTP response |
| LAB-015 | Grafana initially had no Prometheus data source | Resolved by configuring and testing the Prometheus data source |
| LAB-016 | Prometheus targets needed verification after configuration | Resolved by checking target/API status and Node Exporter metrics |

---

## LAB-001 — Docker socket permission denied

### Symptom
Docker commands failed for the ordinary user due to permission to access the Docker daemon socket.

### Diagnostic approach
We distinguished a Docker daemon/command problem from a permissions problem by retrying with elevated privileges.

### Resolution
Used `sudo docker ...` for lab operations.

### Production lesson
Docker daemon access is highly privileged: a user who can control the daemon can usually gain root-equivalent control of the host. In production, don't solve this casually by granting broad access. Use controlled group membership, rootless Docker where appropriate, or an approved platform access mechanism. Check the daemon state and socket permissions separately.

### Evidence / commands
```bash
sudo docker ps
sudo docker network ls
```

**Status:** Resolved for the lab by using `sudo`.

---

## LAB-002 — Terraform/provider state inconsistency and containers with missing IPs

### Symptom
During an early Terraform build, the Docker provider encountered state-related errors (including an `ObjectStatus(0)`-style error), and some containers appeared without the expected IP configuration.

### Diagnostic approach
We inspected Terraform state and the actual Docker objects rather than assuming the HCL alone described the running environment. The lab was manually cleaned up and Terraform was rerun to recover a consistent set of resources.

### Resolution
Cleaned up inconsistent Docker resources and rebuilt the lab through Terraform. Later, the production network and containers were successfully created with explicit addresses.

### Important caveat
The exact underlying cause of the initial provider/state inconsistency was not conclusively established. Do not present this as a proven Terraform bug or a proven provider defect.

### Production lesson
When Terraform state and the real infrastructure disagree:
1. Stop making repeated blind changes.
2. Inspect `terraform state list`, `terraform plan`, and the real resources.
3. Back up state before manual state operations.
4. Determine whether a resource is missing, unmanaged, or incorrectly tracked.
5. Prefer a controlled import/reconciliation or targeted rebuild over deleting state blindly.
6. Never manually edit state unless you understand the consequences.

### Useful checks
```bash
terraform state list
terraform plan
sudo docker ps -a
sudo docker network inspect production-net
```

**Status:** Recovered; root cause uncertain.

---

## LAB-003 — Docker network subnet overlap

### Symptom
A new Docker network could not be created because the selected subnet overlapped an existing Docker network.

### Diagnostic approach
Inspected existing Docker networks and identified that the desired address range conflicted with a range already in use.

### Resolution
Selected a non-overlapping subnet for the production lab network, eventually using `10.10.0.0/24` for `production-net`, with explicit addresses for the nodes.

### Production lesson
Plan IP address management before creating networks. In real environments, check existing LAN, VPN, Docker, Kubernetes, and cloud VPC ranges. Overlap can cause routing ambiguity and connectivity failures. Use an IPAM plan and document allocations.

### Useful checks
```bash
sudo docker network ls
sudo docker network inspect <network-name>
ip route
```

**Status:** Resolved.

---

## LAB-004 — Nginx could not resolve backend names

### Symptom
Nginx reported an upstream/backend name-resolution problem (the error involved `backend-1`).

### Diagnostic approach
Compared the names configured in Nginx with the names actually registered on the Docker network. A name in an upstream configuration must be resolvable in the network context where Nginx runs.

### Resolution
Aligned the Nginx upstream configuration with the actual backend names/addressing. In the current production lab, Nginx uses the explicit backend addresses `10.10.0.11:8080` and `10.10.0.12:8080`.

### Production lesson
For containerized services, verify DNS/service discovery from the caller's network namespace, not just from the host. Validate configuration before reload and test the path end to end.

### Useful checks
```bash
sudo docker network inspect production-net
sudo docker exec nginx-01 getent hosts app-01
sudo docker exec nginx-01 nginx -t
```

**Status:** Resolved.

---

## LAB-005 — Load-balanced requests kept returning the same backend

### Symptom
Repeated requests through Nginx returned the same backend response even though multiple backends were configured.

### Diagnostic approach
We tested the responses from the proxy repeatedly and inspected the backend content/process behavior. The issue was not proven to be a load-balancing algorithm defect; backend responses and their distinct identity needed to be verified.

### Resolution
Corrected the backend response/content so the backend identity could be distinguished, then tested repeated requests. The final loop returned responses from both `app-01` and `app-02`.

### Production lesson
Do not infer load-balancing failure from identical responses until you verify that:
- each backend is healthy and reachable,
- each backend serves a distinct identity/version,
- the proxy configuration is valid,
- connection reuse or balancing policy is understood.

### Verification
```bash
for i in {1..6}; do
  curl -s http://10.10.0.10 | grep "Server:"
done
```

**Status:** Resolved and verified.

---

## LAB-006 — Ubuntu container lacked the expected systemd init process

### Symptom
A basic `ubuntu:24.04` container did not provide `/sbin/init` / the systemd executable in the form required by the lab. This blocked the plan to practice `systemctl`, services, and journald inside each simulated server.

### Diagnostic approach
Inspected the image and found that a minimal base image does not automatically provide a complete systemd environment.

### Resolution
Built a custom image, `linux-production-server`, installing `systemd`, `systemd-sysv`, OpenSSH Server, sudo, networking tools, cron, and other administration utilities. Containers run `/sbin/init` with the privileges needed by this lab.

### Production lesson
Containers are not automatically full virtual machines. Running systemd in a container is possible but requires deliberate image/runtime configuration and has trade-offs. For many production containers, one process per container is preferred; for this specific learning lab, systemd is intentionally included to practice server administration. Use VMs when you need a closer simulation of independent hosts and kernels.

**Status:** Resolved for this educational lab.

---

## LAB-007 — Ansible failed because the locale encoding was not UTF-8

### Symptom
Ansible reported:
```text
Ansible requires the locale encoding to be UTF-8; Detected ISO8859-1.
```
The host had locale settings such as `LANG=en_IN` and other `en_IN` LC variables.

### Diagnostic approach
Inspected the locale environment and system locale. The configured locale did not resolve to UTF-8 in the environment Ansible was using.

### Resolution
Changed the system locale to `en_US.UTF-8` and verified the result. Ansible then ran without needing temporary locale exports.

### Useful checks
```bash
locale
localectl status
cat /etc/default/locale
```

### Production lesson
Locale is part of the runtime environment. For automation hosts and CI runners, standardize locale explicitly and verify it early. Temporary `export` commands can be useful for diagnosis, but a persistent system or service environment should be configured deliberately when that is the intended fix.

**Status:** Resolved permanently on the lab host.

---

## LAB-008 — PC reboot made the lab unavailable

### Symptom
After the PC was shut down/rebooted, lab containers were stopped/exited. Terraform still tracked resources, but the runtime was not available as expected.

### Diagnostic approach
Checked Docker container state, Terraform state, and restart policies. Early in the project, containers used the default/no restart policy. A later recovery required Terraform to recreate several containers, after which Ansible configuration had to be reapplied.

### Resolution
Added:
```hcl
restart = "unless-stopped"
```
to the Docker container resources in Terraform. Applied the change and verified the Docker restart policy. After a subsequent PC reboot, all four original service containers came back up; the application and Nginx load balancing worked again. The monitoring container was later added with the same restart policy.

### Production lesson
Separate desired infrastructure state from runtime lifecycle:
- Terraform defines and reconciles infrastructure.
- Docker restart policies control container restart behavior.
- systemd manages services inside the container.
- Ansible configures software and files inside nodes.

`terraform apply` is not a general-purpose start command for every stopped process; it reconciles resources with the declared configuration. Configure restart policies, test reboot recovery, and document the recovery sequence.

### Useful checks
```bash
sudo docker ps -a
sudo docker inspect -f '{{.Name}} -> {{.HostConfig.RestartPolicy.Name}}' nginx-01 app-01 app-02 db-01 monitoring-01
sudo docker logs <container-name>
```

**Status:** Resolved and tested after reboot.

---

## LAB-009 — Recreated containers lost Ansible-installed configuration

### Symptom
When Terraform recreated containers, software and configuration installed inside the old container instances were no longer present.

### Diagnostic approach
Distinguished persistent infrastructure definitions from configuration applied interactively or by Ansible to a specific container instance. A replacement container starts from its image; changes made only inside the previous writable layer do not automatically transfer.

### Resolution
Re-ran the Ansible playbooks in the correct order to restore the baseline, Node Exporter, Prometheus, Grafana, application service, and Nginx configuration as needed.

### Production lesson
Containers should be treated as replaceable. Use:
- versioned images for baseline packages,
- Ansible or another configuration-management system for repeatable node configuration,
- persistent volumes for data that must survive replacement,
- Terraform for infrastructure,
- documented, idempotent rebuild procedures.

Do not rely on unrecorded manual changes inside a running container.

**Status:** Recovered; playbooks are the repeatable configuration path.

---

## LAB-010 — SSH host-key warnings after container recreation

### Symptom
After recreating containers, SSH could warn that the remote host key had changed.

### Diagnostic approach
Recognized that a newly created container may have a different SSH host key even when it reuses the same IP address. The client's `known_hosts` file still contained the old key.

### Resolution
Removed the stale entry for the affected lab IP using `ssh-keygen -R`, then reconnected and accepted the new key after confirming it belonged to the recreated lab node.

Example:
```bash
ssh-keygen -R 10.10.0.10
```

Repeat for the specific affected lab address only.

### Production lesson
A changed host key can indicate a legitimate rebuild, but it can also indicate a man-in-the-middle attack. Never blindly delete the warning in production. Verify the new host key through a trusted channel or configuration-management/host-identity process before accepting it. For ephemeral lab hosts, document that rebuilding may rotate host keys.

**Status:** Addressed for recreated lab containers.

---

## LAB-011 — Unsupported Node Exporter flag caused service failure

### Symptom
After setting:
```text
--collector.filesystem.fs-types-include=overlay
```
Node Exporter failed to start. systemd showed the service as failed.

### Diagnostic approach
Checked service status and logs:
```bash
systemctl status prometheus-node-exporter --no-pager -l
journalctl -u prometheus-node-exporter -n 30 --no-pager
```

The logs reported:
```text
unknown long flag '--collector.filesystem.fs-types-include'
```

Although the installed version was 1.7.0, that did not mean this packaged binary supported every flag found in upstream documentation or current source.

### Resolution
Removed the unsupported flag, restored the service, then inspected the exact binary's help output:

```bash
prometheus-node-exporter --help 2>&1 \
  | grep -E 'filesystem|fs-types|mount-points'
```

We used the supported `--collector.filesystem.fs-types-exclude` option instead.

### Production lesson
Treat installed binaries and their help output as authoritative. Validate configuration changes on one canary first, then check both the service state and the actual exported metrics. A successful Ansible task is not sufficient evidence that the application is healthy.

**Status:** Resolved.

---

## LAB-012 — Root filesystem metrics were missing from Grafana

### Symptom
The Disk Utilization panel initially showed no usable root-filesystem series. Other metrics were available.

### Diagnostic approach
We followed the metric path from source outward:

1. Queried Node Exporter directly.
2. Confirmed `node_filesystem_size_bytes` existed.
3. Found no `node_filesystem_avail_bytes` series with `mountpoint="/"`.
4. Inspected the root filesystem with `df -hT /`; it was `overlay`.
5. Inspected Node Exporter flags and found `overlay` in the default filesystem-type exclusion regex.
6. Inspected the installed binary rather than assuming unsupported flags would work.

### Resolution
Used Ansible to set a supported filesystem exclusion regex that retained the other exclusions but removed `overlay` from the excluded types. Restarted Node Exporter on all five nodes.

The raw metric then appeared:
```text
node_filesystem_avail_bytes{device="overlay",fstype="overlay",mountpoint="/"} 9.07803860992e+11
```

Grafana could then calculate utilization with:
```promql
100 * (
  1 -
  (
    node_filesystem_avail_bytes{mountpoint="/", fstype="overlay"}
    /
    node_filesystem_size_bytes{mountpoint="/", fstype="overlay"}
  )
)
```

### Production lesson
Debug the telemetry pipeline in order:
**Filesystem → Node Exporter → Prometheus → Grafana.**

Do not assume that a missing graph is a visualization problem. Check target health, raw metrics, labels, collector filters, and the installed binary.

**Container caveat:** All these nodes are containers sharing host-backed storage. Their overlay filesystem statistics do not represent five independent physical disks. Real deployments should distinguish host filesystem capacity, container writable-layer usage, persistent volumes, and ephemeral-storage limits.

**Status:** Resolved and visible in Grafana.

---

## LAB-013 — Grafana was not reachable from the host

### Symptom
Grafana was installed and running inside `monitoring-01`, but the host browser could not access it at `http://localhost:3000`.

### Diagnostic approach
Checked service status and the listening socket:
```bash
systemctl is-active grafana-server
ss -lntp | grep ':3000'
```

Grafana was listening on port 3000 inside the container. The issue was the boundary between the container network and the host.

### Resolution
Added a port publication to the Terraform Docker container resource:
```hcl
ports {
  internal = 3000
  external = 3000
}
```

Applied the Terraform change, which required the monitoring container to be replaced. Then reapplied the Ansible playbooks to restore the monitoring node configuration and verified the published port.

### Production lesson
A service listening inside a container is not automatically reachable from the host or outside the container network. Check:
1. The service's listening socket.
2. Container port publication.
3. Host firewall and network rules.
4. The URL and protocol being used.

Publishing a port exposes a service on the host; in production, bind and firewall it intentionally and use access controls/TLS as required.

**Status:** Resolved.

---

## LAB-014 — Grafana's listening address looked unusual

### Symptom
A check looking specifically for an IPv4 listener did not find Grafana on port 3000, even though the service was active.

### Diagnostic approach
Checked all listeners rather than assuming an IPv4-only address:
```bash
ss -lntp | grep grafana
```

The output showed Grafana listening on `*:3000` (an unspecified address, shown by the system's socket tools as a wildcard listener).

Then checked the HTTP response:
```bash
curl -I http://localhost:3000
```

The server returned an HTTP redirect to `/login`.

### Resolution
No service change was needed for this symptom. The listener and HTTP response confirmed Grafana was operating. Port publication was handled separately in LAB-013.

### Production lesson
Avoid overfitting a diagnostic command to one expected display format. Inspect the full socket output and test the application protocol. A listening socket, a successful HTTP response, and external reachability are three distinct checks.

**Status:** Diagnosed; no independent fault remained.

---

## LAB-015 — Grafana initially had no working Prometheus data source

### Symptom
Grafana needed a data source before it could query the Prometheus metrics.

### Diagnostic approach
Confirmed Prometheus was running on port 9090 on the monitoring node and used its HTTP endpoint as the Grafana data source.

### Resolution
Configured the Prometheus data source in Grafana with:
```text
http://localhost:9090
```
The Grafana **Save & Test** action succeeded in this lab setup.

### Production lesson
The correct URL depends on where Grafana and Prometheus run and which network namespace resolves the address. `localhost` always means the current network namespace; it is not a universal reference to another container or host. In separate containers, use a reachable service name/IP and confirm connectivity from Grafana's own environment.

**Status:** Resolved in the lab's network/port configuration.

---

## LAB-016 — Validate Prometheus target health instead of assuming scrapes work

### Symptom
After installing Node Exporter across the fleet and configuring Prometheus, we needed to establish that all intended nodes were actually being scraped.

### Diagnostic approach
Queried Prometheus target status and verified raw Node Exporter metrics. Initially, four targets were configured; after adding `monitoring-01:9100`, all five targets reported `up`.

### Resolution
Updated the Prometheus scrape configuration to include:
- `10.10.0.10:9100`
- `10.10.0.11:9100`
- `10.10.0.12:9100`
- `10.10.0.20:9100`
- `10.10.0.30:9100`

Reapplied the Prometheus Ansible playbook and confirmed the targets were up.

### Production lesson
A running Prometheus service does not prove that all targets are being scraped. Monitor target health, check scrape errors, and verify that expected series are present. Also alert on missing targets or missing critical metrics.

**Status:** Resolved and verified.

---

## Cross-incident lessons

### 1. Diagnose from evidence, not assumptions
Use the relevant layer's diagnostic tools before changing configuration:
- Docker: `docker ps`, `docker logs`, `docker inspect`, `docker network inspect`
- Terraform: `terraform plan`, `terraform state list`
- Linux: `df`, `findmnt`, `ip`, `ss`, `ps`
- systemd: `systemctl status`, `systemctl cat`
- Logs: `journalctl`
- SSH: `ssh -v`, `ssh-keygen -R` only after identity is verified
- Ansible: playbook output, inventory checks, idempotent reruns
- Prometheus: target status, raw metric queries
- Grafana: query inspector and data-source testing

### 2. Verify at the lowest failing layer first
If Grafana has no data, inspect the exporter before changing the dashboard. If a service is unreachable, check whether it is running and listening before changing firewall rules.

### 3. Separate the roles of the tools
- **Terraform:** declares and reconciles infrastructure.
- **Docker:** runs containers and manages container networks/ports.
- **Ansible:** configures software and operating-system state.
- **systemd:** manages services inside the lab nodes.
- **Prometheus:** scrapes and stores metrics.
- **Node Exporter:** exposes host/container-visible operating-system metrics.
- **Grafana:** queries and visualizes metrics.

### 4. Make recovery repeatable
A rebuilt container should be recoverable from versioned image definitions, Terraform, and Ansible playbooks. Manual changes inside a container are temporary unless captured in an image, playbook, or persistent volume.

### 5. Validate after every change
Check more than whether a command exited successfully. Confirm the service is active, the port is listening, the endpoint responds, the expected metric exists, and the dashboard shows the result.

### 6. Understand the difference between a lab and production
This lab teaches real troubleshooting practices, but Docker containers share a host kernel and host storage. For realistic independent disk, kernel, routing, and failure-domain behavior, use separate VMs or dedicated test environments.

## Portfolio summary

This project has provided practical troubleshooting experience across:

- Docker permissions, networking, restart behavior, and port publishing.
- Terraform state reconciliation and infrastructure recreation.
- Linux filesystems, locale, processes, and service management.
- SSH identity and host-key handling.
- Nginx reverse proxying and backend verification.
- Ansible inventory, configuration deployment, and idempotent recovery.
- Prometheus scraping, Node Exporter collectors, and metric validation.
- Grafana data sources, PromQL queries, and dashboards.

The strongest portfolio story is not simply that the monitoring stack was deployed. It is that faults were investigated across layers, fixes were applied through repeatable configuration, and the results were verified with evidence.
