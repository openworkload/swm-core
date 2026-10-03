# Job accounting and metrics

Sky Port can sample per-job resource usage while a job runs. Porter collects
samples inside the job container and SWM forwards them up the hierarchy to
Sky Port. **Persistence is not implemented yet** -- at Sky Port the samples
are logged only.

See also `HOWTO/JOBS.md` for job scripts and `#SWM` directives, and
`HOWTO/CONTAINERS.md` for the Podman runtime.

## What is sampled

| Metric | Source | When |
|--------|--------|------|
| CPU percent | cgroup v2 `cpu.stat` (`usage_usec`) | Always (if cgroup v2 available) |
| Memory bytes | cgroup v2 `memory.current` | Always (if cgroup v2 available) |
| GPU util / memory | `nvidia-smi` (best effort) | Only if the job requests GPUs (`#SWM gpus` > 0) |

CPU and memory use **cgroup v2 only**. There is no cgroup v1 and no `/proc`
fallback. If cgroup v2 is missing, those fields are skipped (Porter logs once).

Samples are **job-scoped** (the container cgroup), not whole-node totals.

## Configuration

| Setting | Where | Default | Meaning |
|---------|-------|---------|---------|
| `job_metrics_interval` | `priv/base.config` / globals | `15000` | Sample period in milliseconds; `0` disables sampling |

Porter also receives (injected into the job env at RUN time):

| Env | Meaning |
|-----|---------|
| `SWM_METRICS_INTERVAL_MS` | Same interval as the global (ms) |
| `SWM_METRICS_GPU` | `1` if the job requested GPUs, else `0` |

## Forwarding path

```
Porter (any allocated node)
  -> local wm_container
  -> wm_proc (main script) or wm_pmix (rank)
  -> (non-main rank) main job node wm_pmix -> wm_compute
  -> parent SWM (repeat until root)
  -> Sky Port wm_accounting:log_job_metrics/3  (log only)
```

On Sky Port (`wm_core:get_parent()` is `not_found`), metrics are not stored;
they appear in the SWM log as `Job metrics job=... cpu_percent=... mem_bytes=...`.

## Log line fields

Typical INFO fields: `job`, `node`, `ts` (unix ms), `cpu_percent`, `mem_bytes`,
and when GPU sampling is enabled and available: `gpu_util_percent`,
`gpu_mem_bytes`.
