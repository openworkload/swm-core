#include "wm_porter_metrics.h"

#include "wm_io.h"

#include <ei.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <unistd.h>

namespace swm {
namespace {

std::string env_value(const SwmJob &job, const char *key) {
  for (const auto &kv : job.get_env()) {
    if (kv.first == key) {
      return kv.second;
    }
  }
  return "";
}

bool file_readable(const std::string &path) {
  return access(path.c_str(), R_OK) == 0;
}

bool is_cgroup_v2() {
  return file_readable("/sys/fs/cgroup/cgroup.controllers");
}

std::string read_self_cgroup_v2_path() {
  std::ifstream in("/proc/self/cgroup");
  if (!in) {
    return "";
  }
  std::string line;
  while (std::getline(in, line)) {
    // v2 unified hierarchy: "0::/path"
    if (line.rfind("0::", 0) == 0) {
      std::string rel = line.substr(3);
      if (rel.empty()) {
        rel = "/";
      }
      if (rel.front() != '/') {
        rel.insert(rel.begin(), '/');
      }
      return "/sys/fs/cgroup" + rel;
    }
  }
  return "";
}

bool read_usage_usec(const std::string &cgroup_path, uint64_t *out) {
  std::ifstream in(cgroup_path + "/cpu.stat");
  if (!in) {
    return false;
  }
  std::string key;
  uint64_t val = 0;
  while (in >> key >> val) {
    if (key == "usage_usec") {
      *out = val;
      return true;
    }
  }
  return false;
}

bool read_memory_current(const std::string &cgroup_path, uint64_t *out) {
  std::ifstream in(cgroup_path + "/memory.current");
  if (!in) {
    return false;
  }
  uint64_t val = 0;
  in >> val;
  if (!in) {
    return false;
  }
  *out = val;
  return true;
}

unsigned ncpus() {
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  if (n < 1) {
    return 1;
  }
  return static_cast<unsigned>(n);
}

std::string hostname_str() {
  char buf[256];
  if (gethostname(buf, sizeof(buf)) != 0) {
    return "unknown";
  }
  buf[sizeof(buf) - 1] = '\0';
  return std::string(buf);
}

bool query_gpu(double *util_percent, uint64_t *mem_bytes) {
  FILE *fp =
      popen("nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null", "r");
  if (!fp) {
    return false;
  }
  char line[256];
  double util_sum = 0.0;
  uint64_t mem_sum = 0;
  unsigned count = 0;
  while (fgets(line, sizeof(line), fp)) {
    double util = 0.0;
    double mem_mib = 0.0;
    if (sscanf(line, "%lf , %lf", &util, &mem_mib) == 2 || sscanf(line, "%lf,%lf", &util, &mem_mib) == 2) {
      util_sum += util;
      mem_sum += static_cast<uint64_t>(mem_mib * 1024.0 * 1024.0);
      ++count;
    }
  }
  const int rc = pclose(fp);
  if (rc != 0 || count == 0) {
    return false;
  }
  *util_percent = util_sum / static_cast<double>(count);
  *mem_bytes = mem_sum;
  return true;
}

int encode_binary_string(ei_x_buff *x, const std::string &s) {
  return ei_x_encode_binary(x, s.data(), static_cast<int>(s.size()));
}

int send_porter_metrics_term(const std::string &job_id, const std::string &node, int64_t ts_ms, bool have_cpu,
                             double cpu_percent, bool have_mem, uint64_t mem_bytes, bool have_gpu, double gpu_util,
                             uint64_t gpu_mem) {
  ei_x_buff x;
  if (ei_x_new(&x) || ei_x_encode_version(&x) || ei_x_encode_tuple_header(&x, 2) ||
      ei_x_encode_atom(&x, "porter_metrics")) {
    ei_x_free(&x);
    return -1;
  }

  size_t arity = 3;  // job_id, node, ts
  if (have_cpu) {
    ++arity;
  }
  if (have_mem) {
    ++arity;
  }
  if (have_gpu) {
    arity += 2;
  }

  if (ei_x_encode_map_header(&x, arity)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "job_id") || encode_binary_string(&x, job_id)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "node") || encode_binary_string(&x, node)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "ts") || ei_x_encode_longlong(&x, ts_ms)) {
    ei_x_free(&x);
    return -1;
  }
  if (have_cpu) {
    if (ei_x_encode_atom(&x, "cpu_percent") || ei_x_encode_double(&x, cpu_percent)) {
      ei_x_free(&x);
      return -1;
    }
  }
  if (have_mem) {
    if (ei_x_encode_atom(&x, "mem_bytes") || ei_x_encode_ulonglong(&x, mem_bytes)) {
      ei_x_free(&x);
      return -1;
    }
  }
  if (have_gpu) {
    if (ei_x_encode_atom(&x, "gpu_util_percent") || ei_x_encode_double(&x, gpu_util)) {
      ei_x_free(&x);
      return -1;
    }
    if (ei_x_encode_atom(&x, "gpu_mem_bytes") || ei_x_encode_ulonglong(&x, gpu_mem)) {
      ei_x_free(&x);
      return -1;
    }
  }

  const uint64_t buf_bytes = static_cast<uint64_t>(x.index);
  swm_write_exact(&std::cout, x.buff, buf_bytes);
  ei_x_free(&x);
  fflush(stdout);
  return 0;
}

}  // namespace

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job) {
  PorterMetricsConfig cfg;
  const std::string interval_s = env_value(job, "SWM_METRICS_INTERVAL_MS");
  if (!interval_s.empty()) {
    cfg.interval_ms = std::strtoll(interval_s.c_str(), nullptr, 10);
  }
  const std::string gpu_s = env_value(job, "SWM_METRICS_GPU");
  cfg.collect_gpu = (gpu_s == "1" || gpu_s == "true" || gpu_s == "yes");
  return cfg;
}

int64_t porter_metrics_now_ms() {
  using clock = std::chrono::system_clock;
  return std::chrono::duration_cast<std::chrono::milliseconds>(clock::now().time_since_epoch()).count();
}

bool porter_metrics_maybe_send(const SwmJob &job, const PorterMetricsConfig &cfg, PorterMetricsState *state,
                               int64_t now_ms) {
  if (cfg.interval_ms <= 0 || state == nullptr) {
    return true;
  }
  if (state->last_sample_ms != 0 && (now_ms - state->last_sample_ms) < cfg.interval_ms) {
    return true;
  }

  if (!state->cgroup_checked) {
    state->cgroup_checked = true;
    state->cgroup_v2_ok = is_cgroup_v2();
    if (state->cgroup_v2_ok) {
      state->cgroup_path = read_self_cgroup_v2_path();
      if (state->cgroup_path.empty()) {
        state->cgroup_path = "/sys/fs/cgroup";
      }
    } else if (!state->warned_no_v2) {
      state->warned_no_v2 = true;
      swm_logi("cgroup v2 not available; skipping CPU/memory job metrics");
    }
  }

  bool have_cpu = false;
  double cpu_percent = 0.0;
  bool have_mem = false;
  uint64_t mem_bytes = 0;

  if (state->cgroup_v2_ok && !state->cgroup_path.empty()) {
    uint64_t usage_usec = 0;
    if (read_usage_usec(state->cgroup_path, &usage_usec)) {
      if (state->have_cpu_baseline && state->last_sample_ms > 0) {
        const int64_t dt_ms = now_ms - state->last_sample_ms;
        if (dt_ms > 0 && usage_usec >= state->last_usage_usec) {
          const double dt_usec = static_cast<double>(dt_ms) * 1000.0;
          const double delta = static_cast<double>(usage_usec - state->last_usage_usec);
          cpu_percent = 100.0 * delta / (dt_usec * static_cast<double>(ncpus()));
          if (cpu_percent < 0.0) {
            cpu_percent = 0.0;
          }
          have_cpu = true;
        }
      }
      state->last_usage_usec = usage_usec;
      state->have_cpu_baseline = true;
    } else {
      swm_logd("Could not read %s/cpu.stat", state->cgroup_path.c_str());
    }

    if (read_memory_current(state->cgroup_path, &mem_bytes)) {
      have_mem = true;
    } else {
      swm_logd("Could not read %s/memory.current", state->cgroup_path.c_str());
    }
  }

  bool have_gpu = false;
  double gpu_util = 0.0;
  uint64_t gpu_mem = 0;
  if (cfg.collect_gpu) {
    have_gpu = query_gpu(&gpu_util, &gpu_mem);
  }

  state->last_sample_ms = now_ms;
  if (!have_cpu && !have_mem && !have_gpu) {
    return true;
  }

  if (send_porter_metrics_term(job.get_id(), hostname_str(), now_ms, have_cpu, cpu_percent, have_mem, mem_bytes,
                               have_gpu, gpu_util, gpu_mem)) {
    swm_loge("Failed to send porter_metrics");
    return false;
  }
  swm_logd("Sent porter_metrics job=%s cpu=%s mem=%s gpu=%s", job.get_id().c_str(), have_cpu ? "y" : "n",
           have_mem ? "y" : "n", have_gpu ? "y" : "n");
  return true;
}

}  // namespace swm
