#pragma once

#include "wm_job.h"

#include <cstdint>
#include <optional>
#include <string>

namespace swm {

struct PorterMetricsConfig {
  /** Local sample period (ms). 0 disables. */
  int64_t sample_interval_ms = 15000;
  /** How long to aggregate before sending one report to SWM (ms). */
  int64_t report_interval_ms = 120000;
  bool collect_gpu = false;
};

/** One local sample (cgroup / NVML). Absent optionals mean "not available". */
struct PorterMetricsSample {
  std::optional<double> cpu_percent;
  std::optional<uint64_t> mem_bytes;
  std::optional<double> gpu_util_percent;
  std::optional<uint64_t> gpu_mem_bytes;

  [[nodiscard]] bool any() const {
    return cpu_percent.has_value() || mem_bytes.has_value() || gpu_util_percent.has_value() ||
           gpu_mem_bytes.has_value();
  }
};

/** Aggregation window between reports to SWM. */
struct PorterMetricsWindow {
  int64_t start_ms = 0;
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

  void reset(int64_t now_ms);
  void add(const PorterMetricsSample &sample);
  [[nodiscard]] bool ready(int64_t now_ms, int64_t report_interval_ms) const;
  [[nodiscard]] bool empty() const { return samples == 0; }
};

struct PorterMetricsState {
  bool cgroup_v2_ok = false;
  bool cgroup_checked = false;
  bool warned_no_v2 = false;
  std::string cgroup_path;
  uint64_t last_usage_usec = 0;
  int64_t last_sample_ms = 0;
  bool have_cpu_baseline = false;
  PorterMetricsWindow window;
};

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job);
int64_t porter_metrics_now_ms();
/** Sample on sample_interval; send aggregated report on report_interval. */
bool porter_metrics_maybe_send(const SwmJob &job,
                               const PorterMetricsConfig &cfg,
                               PorterMetricsState &state,
                               int64_t now_ms);
/** Flush a partial aggregation window (e.g. job end). */
bool porter_metrics_flush(const SwmJob &job, const PorterMetricsConfig &cfg, PorterMetricsState &state, int64_t now_ms);

}  // namespace swm
