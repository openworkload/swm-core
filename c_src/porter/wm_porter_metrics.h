#pragma once

#include "wm_job.h"

#include <cstdint>
#include <string>

namespace swm {

struct PorterMetricsConfig {
  /** Local sample period (ms). 0 disables. */
  int64_t sample_interval_ms = 15000;
  /** How long to aggregate before sending one report to SWM (ms). */
  int64_t report_interval_ms = 120000;
  bool collect_gpu = false;
};

struct PorterMetricsState {
  bool cgroup_v2_ok = false;
  bool cgroup_checked = false;
  bool warned_no_v2 = false;
  std::string cgroup_path;
  uint64_t last_usage_usec = 0;
  int64_t last_sample_ms = 0;
  bool have_cpu_baseline = false;

  int64_t window_start_ms = 0;
  unsigned samples = 0;
  unsigned cpu_samples = 0;
  unsigned mem_samples = 0;
  unsigned gpu_samples = 0;
  double cpu_sum = 0.0;
  double cpu_max = 0.0;
  double mem_sum = 0.0;
  uint64_t mem_max = 0;
  double gpu_util_sum = 0.0;
  double gpu_util_max = 0.0;
  double gpu_mem_sum = 0.0;
  uint64_t gpu_mem_max = 0;
};

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job);
int64_t porter_metrics_now_ms();
/** Sample on sample_interval; send aggregated report on report_interval. */
bool porter_metrics_maybe_send(const SwmJob &job,
                               const PorterMetricsConfig &cfg,
                               PorterMetricsState *state,
                               int64_t now_ms);
/** Flush a partial aggregation window (e.g. job end). */
bool porter_metrics_flush(const SwmJob &job, const PorterMetricsConfig &cfg, PorterMetricsState *state, int64_t now_ms);

}  // namespace swm
