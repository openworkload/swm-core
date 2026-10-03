# Job accounting and metrics

Sky Port can sample per-job resource usage while a job runs. Porter collects
local samples inside the job container, **aggregates them for a report window**
(default 2 minutes), then sends one summary to SWM. SWM forwards summaries up
the hierarchy to Sky Port. At Sky Port the latest values are exported as
**Prometheus gauges** on a cleartext scrape endpoint. Time series are stored by
Prometheus (no separate metrics database in SWM).

See also `HOWTO/JOBS.md` for job scripts and `#SWM` directives, and
`HOWTO/CONTAINERS.md` for the Podman runtime.

## What is sampled

| Metric | Source | When |
|--------|--------|------|
| CPU percent | cgroup v2 `cpu.stat` (`usage_usec`) | Always (if cgroup v2 available) |
| Memory bytes | cgroup v2 `memory.current` | Always (if cgroup v2 available) |
| GPU util / memory | **NVML** (`libnvidia-ml`, dlopen) | Only if the job requests GPUs (`#SWM gpus` > 0) |

CPU and memory use **cgroup v2 only**. There is no cgroup v1 and no `/proc`
fallback. If cgroup v2 is missing, those fields are skipped (Porter logs once).

GPU metrics use NVML in-process (not `nvidia-smi`). If NVML is unavailable in
the container, GPU fields are omitted.

Samples are **job-scoped** (the container cgroup), not whole-node totals.

## Aggregation

Porter samples locally every `job_metrics_interval` (default 15s), accumulates
avg/max over `job_metrics_report_interval` (default **120000 ms / 2 minutes**),
then emits one `{porter_metrics, Map}` to SWM. A partial window is flushed when
the job process exits.

Reported fields (when present): `cpu_percent` / `cpu_percent_max`,
`mem_bytes` / `mem_bytes_max`, `gpu_util_percent` / `gpu_util_percent_max`,
`gpu_mem_bytes` / `gpu_mem_bytes_max`, plus `samples` and `window_ms`.

## Configuration

| Setting | Where | Default | Meaning |
|---------|-------|---------|---------|
| `job_metrics_interval` | `priv/base.config` / globals | `15000` | Local sample period (ms); `0` disables |
| `job_metrics_report_interval` | `priv/base.config` / globals | `120000` | Aggregation / report period to SWM (ms); `0` disables |
| `job_metrics_port` | `priv/base.config` / globals | `9568` | Cleartext Prometheus scrape port (`/metrics`); `0` disables |

Porter also receives (injected into the job env at RUN time):

| Env | Meaning |
|-----|---------|
| `SWM_METRICS_INTERVAL_MS` | Local sample period (ms) |
| `SWM_METRICS_REPORT_MS` | Report / aggregation period (ms) |
| `SWM_METRICS_GPU` | `1` if the job requested GPUs, else `0` |

## Forwarding path

```
Porter (sample + 2min aggregate on compute node)
  -> local wm_container
  -> wm_proc (main script) or wm_pmix (rank)
  -> (non-main rank) main job node wm_pmix -> wm_compute
  -> parent SWM (repeat until root)
  -> Sky Port wm_accounting:log_job_metrics/3
  -> wm_job_metrics gauges + GET :9568/metrics
  -> Prometheus scrape (podman compose)
```

## Prometheus export

On Sky Port, each metrics report updates gauges (labels `job_id`, `node`):

- `swm_job_cpu_percent` / `swm_job_cpu_percent_max`
- `swm_job_mem_bytes` / `swm_job_mem_bytes_max`
- `swm_job_gpu_util_percent` / `swm_job_gpu_util_percent_max`
- `swm_job_gpu_mem_bytes` / `swm_job_gpu_mem_bytes_max`

Scrape URL: `http://skyport-dev:9568/metrics` (or `http://127.0.0.1:9568/metrics`
from the host when the debug container publishes the port).

### Local Prometheus (podman compose)

With `skyport-dev` running on network `skyportnet-dev` (and SWM up so
`:9568/metrics` is listening):

```bash
make prometheus-up    # podman compose -f compose.yml up -d
# UI / API: http://127.0.0.1:9090
# Targets: http://127.0.0.1:9090/targets
make prometheus-down
```

Config: `priv/container/prometheus/prometheus.yml` and root `compose.yml`.
