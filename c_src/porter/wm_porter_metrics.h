#pragma once

#include "wm_job.h"

#include <cstdint>
#include <string>

namespace swm {

struct PorterMetricsConfig {
  int64_t interval_ms = 15000;
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
};

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job);
int64_t porter_metrics_now_ms();
bool porter_metrics_maybe_send(const SwmJob &job, const PorterMetricsConfig &cfg, PorterMetricsState *state,
                               int64_t now_ms);

}  // namespace swm
