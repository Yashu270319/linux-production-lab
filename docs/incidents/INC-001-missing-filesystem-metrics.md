# Incident Report: Missing Disk Filesystem Metrics in Prometheus and Grafana

**Incident ID:** INC-001
**Environment:** Linux Production Lab
**Severity:** Low — monitoring visibility issue
**Component:** Node Exporter → Prometheus → Grafana
**Affected infrastructure:** `nginx-01`, `app-01`, `app-02`, `db-01`, `monitoring-01`
**Status:** Resolved

## 1. Incident summary

The Grafana dashboard displayed CPU and memory metrics for our five Linux nodes, but the Disk Utilization panel initially had no usable data.

Prometheus was running, Node Exporter was installed, and the targets were reachable. However, the expected root filesystem metrics for `mountpoint="/"` were missing.

The issue was not caused by Grafana itself. The underlying problem was the filesystem collector configuration in the installed Ubuntu-packaged Node Exporter.

By default, this Node Exporter build excluded the `overlay` filesystem type. Our Linux nodes were Docker containers, and their root filesystem was reported as `overlay`. Consequently, the collector omitted the filesystem we wanted to monitor.

## 2. Expected versus actual behavior

### Expected behavior

Each node should expose filesystem metrics such as:

- `node_filesystem_size_bytes`: filesystem capacity.
- `node_filesystem_avail_bytes`: space available to non-root users.
- `node_filesystem_free_bytes`: filesystem space available, including space that may be reserved for root.

Prometheus should scrape these metrics, allowing Grafana to calculate filesystem utilization.

### Actual behavior

Node Exporter exposed filesystem metrics for container-mounted files such as `/etc/hostname`, `/etc/hosts`, and `/etc/resolv.conf`, but it did not expose the root mount `/`.

The Grafana query consequently returned no usable root-filesystem series.

## 3. Investigation and troubleshooting timeline

### Step 1 — Confirm that filesystem metrics existed

We queried the Node Exporter endpoint directly:

```bash
curl -s http://10.10.0.11:9100/metrics \
  | grep 'node_filesystem_size_bytes'
```

Filesystem metrics existed, but their labels showed that the expected root mount was absent.

**Reasoning:** Node Exporter was reachable and producing metrics. This made a complete exporter outage unlikely. We needed to investigate metric selection and collection.

### Step 2 — Check the expected mountpoint

```bash
curl -s http://10.10.0.11:9100/metrics \
  | grep 'node_filesystem_avail_bytes' \
  | grep 'mountpoint="/"'
```

The command returned no output. We then checked all available-space metrics and found only the `/etc/...` mounts.

**Conclusion:** The problem existed before Prometheus and Grafana processed the metrics. We needed to inspect the exporter and its environment.

### Step 3 — Inspect the actual filesystem

We used Ansible to inspect the application server:

```bash
ansible -i inventory/hosts.ini app-01 -b \
  -m shell -a "df -hT / && mount | head -20"
```

The root filesystem was reported as `overlay`, mounted at `/`.

This revealed the key environmental detail: our node was a container with an overlay root filesystem, not a conventional standalone Linux server with a directly mounted root partition.

### Step 4 — Inspect the Node Exporter configuration

We checked how systemd launched Node Exporter:

```bash
ansible -i inventory/hosts.ini app-01 -b \
  -m shell -a \
  "systemctl cat prometheus-node-exporter | grep ExecStart"
```

The service used:

```text
ExecStart=/usr/bin/prometheus-node-exporter $ARGS
```

We also inspected `/etc/default/prometheus-node-exporter`. Initially, `ARGS` was empty.

### Step 5 — Check the actual binary's supported flags

The installed version was Node Exporter `1.7.0`, packaged for Ubuntu.

We inspected the binary's own help output:

```bash
ansible -i inventory/hosts.ini app-01 -b -m shell -a \
  "prometheus-node-exporter --help 2>&1 | grep -E 'filesystem|fs-types|mount-points'"
```

The output showed support for:

- `--collector.filesystem.fs-types-exclude`
- `--collector.filesystem.mount-points-exclude`

The default filesystem-type exclusion expression contained `overlay`.

**Root cause identified:** Node Exporter's filesystem collector excluded the filesystem type used by our container root.

### Step 6 — Attempt a configuration change and recover

We first attempted to use:

```text
--collector.filesystem.fs-types-include=overlay
```

The installed binary did not support that flag. The service failed to start and systemd eventually reported that it had failed too many times.

We diagnosed the failure using:

```bash
systemctl status prometheus-node-exporter --no-pager -l
journalctl -u prometheus-node-exporter -n 30 --no-pager
```

The journal explicitly reported:

```text
unknown long flag '--collector.filesystem.fs-types-include'
```

We removed the unsupported argument, restored the exporters, and verified that the service was active on all five nodes.

**Lesson:** Never infer support for a command-line flag from a version number alone. The installed binary and its logs are authoritative for that environment.

### Step 7 — Apply the supported configuration through Ansible

We changed the Node Exporter `ARGS` setting to use the supported exclusion flag, preserving the default exclusions while removing `overlay` from the excluded filesystem types.

The relevant configuration became:

```text
ARGS="--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"
```

We deployed it across all five nodes using:

```bash
ansible-playbook -i inventory/hosts.ini playbooks/node-exporter.yml
```

Ansible updated the configuration and restarted Node Exporter on each node.

### Step 8 — Verify the fix at the source

We queried the raw metric again:

```bash
curl -s http://10.10.0.11:9100/metrics \
  | grep 'node_filesystem_avail_bytes' \
  | grep 'mountpoint="/"'
```

This time, the output included:

```text
node_filesystem_avail_bytes{device="overlay",fstype="overlay",mountpoint="/"} 9.07803860992e+11
```

The metric was now present.

We then configured the Grafana Disk Utilization panel using:

```promql
100 * (
  1 -
  (
    node_filesystem_avail_bytes{
      mountpoint="/",
      fstype="overlay"
    }
    /
    node_filesystem_size_bytes{
      mountpoint="/",
      fstype="overlay"
    }
  )
)
```

The panel began displaying filesystem-utilization time series for the monitored nodes.

## 4. Root cause analysis

**Primary root cause:** Node Exporter's default filesystem-type exclusion filter excluded `overlay`, while our container root filesystems used that type.

**Contributing factors:**

1. The infrastructure ran in Docker containers rather than on five independent physical or virtual machines.
2. The initial Grafana query assumed the desired root filesystem would be included in the exported metrics.
3. We investigated the query before fully confirming the collector's filesystem filters.
4. We attempted to use a flag unsupported by the installed distribution package.
5. The unsupported flag caused the exporter service to fail, creating a secondary monitoring issue.

**What was not the root cause:**

- Grafana itself.
- Prometheus scraping in general.
- Network connectivity between Prometheus and Node Exporter.
- The absence of a root filesystem inside the containers.

## 5. How we could have diagnosed it faster

A more efficient diagnostic sequence would be:

1. Check Prometheus target health.
2. Query the metric directly from the Node Exporter endpoint.
3. Check whether the expected `mountpoint` label exists.
4. Inspect `df -hT /` to identify the filesystem type.
5. Inspect the collector's supported flags and default exclusions.
6. Make the smallest supported configuration change.
7. Restart the service and verify the raw metric.
8. Only then update or troubleshoot the Grafana panel.

The central principle is to troubleshoot the metric pipeline from the source outward:

**Filesystem → Node Exporter → Prometheus → Grafana**

This avoids wasting time changing a dashboard when the metric was never being exported.

## 6. How this should be handled in a real-world implementation

The diagnosis is transferable to production, but the correct configuration depends on the actual infrastructure.

### A. On physical servers or virtual machines

A conventional Linux server might use an ext4 or XFS root filesystem.

- Identify the actual root filesystem using `findmnt /` or `df -hT /`.
- Check the collector's filters and exported filesystem labels.
- Confirm whether the filesystem type is intentionally excluded.
- Change the collector configuration only if the missing filesystem is genuinely needed.
- Verify that filesystem metrics are present after deployment.

Do not blindly remove every default exclusion. Filesystems such as `proc`, `sysfs`, `tmpfs`, and other virtual mounts can create noisy or misleading results if collected indiscriminately.

### B. In Docker and containerized environments

A container's root filesystem is commonly an overlay filesystem backed by storage on the host.

Enabling overlay metrics may expose the root mount, but it does **not** automatically provide independent disk-capacity accounting for every container. Several containers can report the same underlying host filesystem capacity. A container can also exhaust its writable layer or a configured storage limit without that condition being accurately represented by a simple filesystem-utilization percentage.

For real production monitoring, distinguish between:

- **Host filesystem capacity:** Monitor the host's actual root and data filesystems.
- **Container writable-layer usage:** Monitor per-container writable-layer consumption and limits using appropriate container-runtime telemetry.
- **Persistent volumes:** Monitor the filesystems used by persistent data volumes.
- **Container ephemeral-storage limits:** Alert on usage relative to the configured limit where the platform exposes it.

For our lab, the overlay metrics are useful for learning the collector and query pipeline. They should not be treated as proof that each container has an independent disk.

### C. In Kubernetes

A production implementation would normally combine node-level filesystem monitoring with container and volume metrics. Depending on the environment, that can include:

- Node Exporter for node-level filesystem capacity.
- Kubelet/cAdvisor metrics for container filesystem usage.
- Kubelet volume statistics for persistent-volume capacity and usage.
- Kubernetes ephemeral-storage requests and limits.
- Alerts for node disk pressure and persistent volumes approaching capacity.

The exact metric sources depend on the Kubernetes distribution and monitoring stack.

### D. Configuration management and safe rollout

In a production environment, the fix should be managed through Ansible or another configuration-management system rather than editing each server manually.

A safer deployment procedure would be:

1. Confirm the supported flags on the deployed Node Exporter build.
2. Change the configuration in version control.
3. Test the configuration on one canary node.
4. Validate that Node Exporter starts and the expected metrics appear.
5. Confirm Prometheus reports the target as healthy.
6. Roll the change out to the remaining nodes.
7. Keep a rollback path if the exporter fails to start.

The Ansible playbook should also validate service health after a restart. A successful playbook run alone does not prove that the service is healthy.

### E. Alerting and dashboards

In production, a disk dashboard should be accompanied by alerts. Example starting thresholds might be:

- Warning: filesystem usage above 80%.
- Critical: filesystem usage above 90%.
- Additional alerts for low absolute free space, inode exhaustion, and rapidly increasing disk usage.

Thresholds should be tuned to filesystem size, workload, growth rate, and recovery time. Percentage usage alone is not enough: 90% of a 10 GB filesystem and 90% of a 10 TB filesystem have very different operational implications.

Alerts should also account for mountpoints, filesystem types, read-only mounts, expected ephemeral filesystems, and the possibility that a metric is missing entirely.

## 7. Preventive actions

| Action | Purpose |
|---|---|
| Keep exporter configuration in Ansible | Make the fix reproducible |
| Inspect actual binary flags before configuring collectors | Avoid unsupported options |
| Validate metrics at the exporter before debugging Grafana | Localize failures faster |
| Add a service-health check after configuration changes | Catch failed restarts |
| Monitor filesystem capacity and free bytes | Detect capacity risks |
| Distinguish host, container, and volume storage | Avoid misleading capacity reporting |
| Version-control monitoring configuration | Make changes reviewable and reversible |
| Add an alert for missing expected metrics | Detect silent monitoring gaps |

## 8. Final outcome

The incident was resolved by adjusting the Node Exporter filesystem exclusion filter to allow `overlay`, using a flag supported by the installed binary.

The root filesystem metric was verified directly at the exporter, and Grafana subsequently displayed the disk-utilization series.

The main operational lesson is that a missing dashboard metric is not necessarily a dashboard problem. Diagnose the entire telemetry path, inspect the actual runtime environment, use the installed binary's supported options, and verify every change at the source before moving downstream.

**Portfolio evidence:** This incident demonstrates Linux filesystem inspection, systemd and journal troubleshooting, Node Exporter configuration, Ansible-based fleet management, Prometheus metric validation, Grafana query construction, and awareness of the limitations of containerized filesystem telemetry.
