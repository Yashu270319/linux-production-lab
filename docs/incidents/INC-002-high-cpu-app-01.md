# INC-002: High CPU Utilization on app-01

## Incident Summary
- **Affected host:** app-01
- **Host IP:** 10.10.0.11
- **Severity:** Low (controlled lab exercise)
- **Status:** Resolved
- **Incident type:** Runaway process / CPU saturation

## Symptoms
CPU utilization increased above the host's observed baseline.
Prometheus reported approximately 36% CPU utilization during the test.

## Investigation
The following command identified the process consuming CPU:

```bash
sudo docker exec app-01 ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head
```

Observed process:
- **Process:** yes
- **PID:** 3440
- **CPU usage:** approximately 99.9%

The `yes` process was intentionally started for this controlled exercise.

## Root Cause
A deliberately launched `yes` process continuously generated output redirected to
`/dev/null`, consuming approximately one CPU core.

## Remediation
The test process was terminated:

```bash
sudo docker exec app-01 pkill -x yes
```

The process list confirmed that `yes` was no longer running.

## Recovery Verification
Prometheus CPU utilization readings for app-01:

| Stage | CPU utilization |
|---|---:|
| Baseline | approximately 14% |
| During incident | approximately 36% |
| Shortly after termination | approximately 33% |
| Later recovery reading | approximately 9.1% |

The Prometheus query used a five-minute rate window, so its readings changed gradually after remediation.

## Lessons Learned
1. Use process-level tools to identify the source of CPU consumption.
2. Correlate process evidence with monitoring metrics.
3. Verify recovery after remediation rather than assuming the incident is resolved.
4. A five-minute Prometheus rate window smooths short-term changes.

## Prevention and Follow-up
- Establish CPU alert thresholds appropriate to the workload.
- Investigate repeated CPU spikes and identify the process or service responsible.
- Consider service-level CPU limits where appropriate.
- Repeat the exercise using a real system service to practise a more production-like investigation.
