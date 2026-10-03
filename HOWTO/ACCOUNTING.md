# Job accounting and metrics

Sky Port can sample per-job resource usage while a job runs. Porter collects
local samples inside the job container, **aggregates them for a report window**
(default 2 minutes), then sends one summary to SWM. SWM forwards summaries up
the hierarchy to Sky Port. **Persistence is not implemented yet** -- at Sky Port
the reports are logged only.

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
  -> Sky Port wm_accounting:log_job_metrics/3  (log only)
```

On Sky Port (`wm_core:get_parent()` is `not_found`), metrics are not stored;
they appear in the SWM log as `Job metrics job=... samples=... cpu_percent=...`.

## Log line fields

Typical INFO fields: `job`, `node`, `ts` (unix ms), `samples`, `window_ms`,
`cpu_percent`, `cpu_percent_max`, `mem_bytes`, `mem_bytes_max`, and when GPU
sampling is enabled and NVML is available: `gpu_util_percent`, `gpu_mem_bytes`.
