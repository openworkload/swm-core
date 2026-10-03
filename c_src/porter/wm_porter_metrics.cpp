#include "wm_porter_metrics.h"

#include "wm_io.h"

#include <dlfcn.h>
#include <ei.h>
#include <unistd.h>

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>

namespace swm {
namespace {

// Minimal NVML types/decls so we do not require CUDA headers at build time.
using nvmlReturn_t = int;
using nvmlDevice_t = void *;
constexpr nvmlReturn_t NVML_SUCCESS = 0;

struct nvmlUtilization_t {
  unsigned int gpu;
  unsigned int memory;
};

struct nvmlMemory_t {
  unsigned long long total;
  unsigned long long free;
  unsigned long long used;
};

using nvmlInit_fn = nvmlReturn_t (*)();
using nvmlShutdown_fn = nvmlReturn_t (*)();
using nvmlDeviceGetCount_fn = nvmlReturn_t (*)(unsigned int *);
using nvmlDeviceGetHandleByIndex_fn = nvmlReturn_t (*)(unsigned int, nvmlDevice_t *);
using nvmlDeviceGetUtilizationRates_fn = nvmlReturn_t (*)(nvmlDevice_t, nvmlUtilization_t *);
using nvmlDeviceGetMemoryInfo_fn = nvmlReturn_t (*)(nvmlDevice_t, nvmlMemory_t *);

struct NvmlLib {
  void *handle = nullptr;
  nvmlInit_fn init = nullptr;
  nvmlShutdown_fn shutdown = nullptr;
  nvmlDeviceGetCount_fn device_get_count = nullptr;
  nvmlDeviceGetHandleByIndex_fn device_get_handle = nullptr;
  nvmlDeviceGetUtilizationRates_fn device_get_util = nullptr;
  nvmlDeviceGetMemoryInfo_fn device_get_memory = nullptr;
  bool init_ok = false;
  bool load_attempted = false;
};

NvmlLib &nvml_lib() {
  static NvmlLib lib;
  return lib;
}

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

bool load_nvml() {
  NvmlLib &lib = nvml_lib();
  if (lib.load_attempted) {
    return lib.init_ok;
  }
  lib.load_attempted = true;

  const char *candidates[] = {"libnvidia-ml.so.1", "libnvidia-ml.so", nullptr};
  for (int i = 0; candidates[i] != nullptr; ++i) {
    lib.handle = dlopen(candidates[i], RTLD_LAZY | RTLD_LOCAL);
    if (lib.handle != nullptr) {
      break;
    }
  }
  if (lib.handle == nullptr) {
    swm_logd("NVML not available: %s", dlerror());
    return false;
  }

  lib.init = reinterpret_cast<nvmlInit_fn>(dlsym(lib.handle, "nvmlInit_v2"));
  if (lib.init == nullptr) {
    lib.init = reinterpret_cast<nvmlInit_fn>(dlsym(lib.handle, "nvmlInit"));
  }
  lib.shutdown = reinterpret_cast<nvmlShutdown_fn>(dlsym(lib.handle, "nvmlShutdown"));
  lib.device_get_count = reinterpret_cast<nvmlDeviceGetCount_fn>(dlsym(lib.handle, "nvmlDeviceGetCount_v2"));
  if (lib.device_get_count == nullptr) {
    lib.device_get_count = reinterpret_cast<nvmlDeviceGetCount_fn>(dlsym(lib.handle, "nvmlDeviceGetCount"));
  }
  lib.device_get_handle =
      reinterpret_cast<nvmlDeviceGetHandleByIndex_fn>(dlsym(lib.handle, "nvmlDeviceGetHandleByIndex_v2"));
  if (lib.device_get_handle == nullptr) {
    lib.device_get_handle =
        reinterpret_cast<nvmlDeviceGetHandleByIndex_fn>(dlsym(lib.handle, "nvmlDeviceGetHandleByIndex"));
  }
  lib.device_get_util =
      reinterpret_cast<nvmlDeviceGetUtilizationRates_fn>(dlsym(lib.handle, "nvmlDeviceGetUtilizationRates"));
  lib.device_get_memory = reinterpret_cast<nvmlDeviceGetMemoryInfo_fn>(dlsym(lib.handle, "nvmlDeviceGetMemoryInfo"));

  if (lib.init == nullptr || lib.device_get_count == nullptr || lib.device_get_handle == nullptr ||
      lib.device_get_util == nullptr || lib.device_get_memory == nullptr) {
    swm_logi("NVML symbols incomplete; GPU metrics disabled");
    dlclose(lib.handle);
    lib.handle = nullptr;
    return false;
  }

  if (lib.init() != NVML_SUCCESS) {
    swm_logi("nvmlInit failed; GPU metrics disabled");
    dlclose(lib.handle);
    lib.handle = nullptr;
    return false;
  }
  lib.init_ok = true;
  swm_logd("NVML loaded for job GPU metrics");
  return true;
}

bool query_gpu_nvml(double *util_percent, uint64_t *mem_bytes) {
  if (!load_nvml()) {
    return false;
  }
  NvmlLib &lib = nvml_lib();
  unsigned int count = 0;
  if (lib.device_get_count(&count) != NVML_SUCCESS || count == 0) {
    return false;
  }

  double util_sum = 0.0;
  uint64_t mem_sum = 0;
  unsigned ok = 0;
  for (unsigned int i = 0; i < count; ++i) {
    nvmlDevice_t dev = nullptr;
    if (lib.device_get_handle(i, &dev) != NVML_SUCCESS) {
      continue;
    }
    nvmlUtilization_t util {};
    nvmlMemory_t mem {};
    if (lib.device_get_util(dev, &util) != NVML_SUCCESS) {
      continue;
    }
    if (lib.device_get_memory(dev, &mem) != NVML_SUCCESS) {
      continue;
    }
    util_sum += static_cast<double>(util.gpu);
    mem_sum += static_cast<uint64_t>(mem.used);
    ++ok;
  }
  if (ok == 0) {
    return false;
  }
  *util_percent = util_sum / static_cast<double>(ok);
  *mem_bytes = mem_sum;
  return true;
}

void reset_window(PorterMetricsState *state, int64_t now_ms) {
  state->window_start_ms = now_ms;
  state->samples = 0;
  state->cpu_samples = 0;
  state->mem_samples = 0;
  state->gpu_samples = 0;
  state->cpu_sum = 0.0;
  state->cpu_max = 0.0;
  state->mem_sum = 0.0;
  state->mem_max = 0;
  state->gpu_util_sum = 0.0;
  state->gpu_util_max = 0.0;
  state->gpu_mem_sum = 0.0;
  state->gpu_mem_max = 0;
}

void accumulate_sample(PorterMetricsState *state,
                       bool have_cpu,
                       double cpu_percent,
                       bool have_mem,
                       uint64_t mem_bytes,
                       bool have_gpu,
                       double gpu_util,
                       uint64_t gpu_mem) {
  if (!have_cpu && !have_mem && !have_gpu) {
    return;
  }
  ++state->samples;
  if (have_cpu) {
    state->cpu_sum += cpu_percent;
    if (state->cpu_samples == 0 || cpu_percent > state->cpu_max) {
      state->cpu_max = cpu_percent;
    }
    ++state->cpu_samples;
  }
  if (have_mem) {
    state->mem_sum += static_cast<double>(mem_bytes);
    if (mem_bytes > state->mem_max) {
      state->mem_max = mem_bytes;
    }
    ++state->mem_samples;
  }
  if (have_gpu) {
    state->gpu_util_sum += gpu_util;
    if (state->gpu_samples == 0 || gpu_util > state->gpu_util_max) {
      state->gpu_util_max = gpu_util;
    }
    state->gpu_mem_sum += static_cast<double>(gpu_mem);
    if (gpu_mem > state->gpu_mem_max) {
      state->gpu_mem_max = gpu_mem;
    }
    ++state->gpu_samples;
  }
}

int encode_binary_string(ei_x_buff *x, const std::string &s) {
  return ei_x_encode_binary(x, s.data(), static_cast<int>(s.size()));
}

int send_aggregated_metrics(const std::string &job_id,
                            const std::string &node,
                            int64_t ts_ms,
                            const PorterMetricsState &state) {
  if (state.samples == 0) {
    return 0;
  }

  const bool have_cpu = state.cpu_samples > 0;
  const bool have_mem = state.mem_samples > 0;
  const bool have_gpu = state.gpu_samples > 0;
  const double cpu_avg = have_cpu ? state.cpu_sum / static_cast<double>(state.cpu_samples) : 0.0;
  const uint64_t mem_avg =
      have_mem ? static_cast<uint64_t>(std::llround(state.mem_sum / static_cast<double>(state.mem_samples))) : 0;
  const double gpu_util_avg = have_gpu ? state.gpu_util_sum / static_cast<double>(state.gpu_samples) : 0.0;
  const uint64_t gpu_mem_avg =
      have_gpu ? static_cast<uint64_t>(std::llround(state.gpu_mem_sum / static_cast<double>(state.gpu_samples))) : 0;
  const int64_t window_ms = ts_ms - state.window_start_ms;

  ei_x_buff x;
  if (ei_x_new(&x) || ei_x_encode_version(&x) || ei_x_encode_tuple_header(&x, 2) ||
      ei_x_encode_atom(&x, "porter_metrics")) {
    ei_x_free(&x);
    return -1;
  }

  // Base: job_id, node, ts, samples, window_ms
  size_t arity = 5;
  if (have_cpu) {
    arity += 2;  // avg + max
  }
  if (have_mem) {
    arity += 2;
  }
  if (have_gpu) {
    arity += 4;  // util avg/max, mem avg/max
  }

  if (ei_x_encode_map_header(&x, arity)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "job_id") || encode_binary_string(&x, job_id) || ei_x_encode_atom(&x, "node") ||
      encode_binary_string(&x, node) || ei_x_encode_atom(&x, "ts") || ei_x_encode_longlong(&x, ts_ms) ||
      ei_x_encode_atom(&x, "samples") || ei_x_encode_ulong(&x, state.samples) || ei_x_encode_atom(&x, "window_ms") ||
      ei_x_encode_longlong(&x, window_ms > 0 ? window_ms : 0)) {
    ei_x_free(&x);
    return -1;
  }
  if (have_cpu) {
    if (ei_x_encode_atom(&x, "cpu_percent") || ei_x_encode_double(&x, cpu_avg) ||
        ei_x_encode_atom(&x, "cpu_percent_max") || ei_x_encode_double(&x, state.cpu_max)) {
      ei_x_free(&x);
      return -1;
    }
  }
  if (have_mem) {
    if (ei_x_encode_atom(&x, "mem_bytes") || ei_x_encode_ulonglong(&x, mem_avg) ||
        ei_x_encode_atom(&x, "mem_bytes_max") || ei_x_encode_ulonglong(&x, state.mem_max)) {
      ei_x_free(&x);
      return -1;
    }
  }
  if (have_gpu) {
    if (ei_x_encode_atom(&x, "gpu_util_percent") || ei_x_encode_double(&x, gpu_util_avg) ||
        ei_x_encode_atom(&x, "gpu_util_percent_max") || ei_x_encode_double(&x, state.gpu_util_max) ||
        ei_x_encode_atom(&x, "gpu_mem_bytes") || ei_x_encode_ulonglong(&x, gpu_mem_avg) ||
        ei_x_encode_atom(&x, "gpu_mem_bytes_max") || ei_x_encode_ulonglong(&x, state.gpu_mem_max)) {
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

bool take_sample(const PorterMetricsConfig &cfg,
                 PorterMetricsState *state,
                 int64_t now_ms,
                 bool *have_cpu,
                 double *cpu_percent,
                 bool *have_mem,
                 uint64_t *mem_bytes,
                 bool *have_gpu,
                 double *gpu_util,
                 uint64_t *gpu_mem) {
  *have_cpu = false;
  *have_mem = false;
  *have_gpu = false;
  *cpu_percent = 0.0;
  *mem_bytes = 0;
  *gpu_util = 0.0;
  *gpu_mem = 0;

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

  if (state->cgroup_v2_ok && !state->cgroup_path.empty()) {
    uint64_t usage_usec = 0;
    if (read_usage_usec(state->cgroup_path, &usage_usec)) {
      if (state->have_cpu_baseline && state->last_sample_ms > 0) {
        const int64_t dt_ms = now_ms - state->last_sample_ms;
        if (dt_ms > 0 && usage_usec >= state->last_usage_usec) {
          const double dt_usec = static_cast<double>(dt_ms) * 1000.0;
          const double delta = static_cast<double>(usage_usec - state->last_usage_usec);
          *cpu_percent = 100.0 * delta / (dt_usec * static_cast<double>(ncpus()));
          if (*cpu_percent < 0.0) {
            *cpu_percent = 0.0;
          }
          *have_cpu = true;
        }
      }
      state->last_usage_usec = usage_usec;
      state->have_cpu_baseline = true;
    } else {
      swm_logd("Could not read %s/cpu.stat", state->cgroup_path.c_str());
    }

    if (read_memory_current(state->cgroup_path, mem_bytes)) {
      *have_mem = true;
    } else {
      swm_logd("Could not read %s/memory.current", state->cgroup_path.c_str());
    }
  }

  if (cfg.collect_gpu) {
    *have_gpu = query_gpu_nvml(gpu_util, gpu_mem);
  }

  state->last_sample_ms = now_ms;
  return *have_cpu || *have_mem || *have_gpu;
}

bool flush_window(const SwmJob &job, PorterMetricsState *state, int64_t now_ms) {
  if (state->samples == 0) {
    reset_window(state, now_ms);
    return true;
  }
  if (send_aggregated_metrics(job.get_id(), hostname_str(), now_ms, *state)) {
    swm_loge("Failed to send aggregated porter_metrics");
    return false;
  }
  swm_logd("Sent aggregated porter_metrics job=%s samples=%u window_ms=%lld",
           job.get_id().c_str(),
           state->samples,
           static_cast<long long>(now_ms - state->window_start_ms));
  reset_window(state, now_ms);
  return true;
}

}  // namespace

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job) {
  PorterMetricsConfig cfg;
  const std::string sample_s = env_value(job, "SWM_METRICS_INTERVAL_MS");
  if (!sample_s.empty()) {
    cfg.sample_interval_ms = std::strtoll(sample_s.c_str(), nullptr, 10);
  }
  const std::string report_s = env_value(job, "SWM_METRICS_REPORT_MS");
  if (!report_s.empty()) {
    cfg.report_interval_ms = std::strtoll(report_s.c_str(), nullptr, 10);
  }
  if (cfg.report_interval_ms > 0 && cfg.sample_interval_ms > cfg.report_interval_ms) {
    // At least one sample per report window.
    cfg.sample_interval_ms = cfg.report_interval_ms;
  }
  const std::string gpu_s = env_value(job, "SWM_METRICS_GPU");
  cfg.collect_gpu = (gpu_s == "1" || gpu_s == "true" || gpu_s == "yes");
  return cfg;
}

int64_t porter_metrics_now_ms() {
  using clock = std::chrono::system_clock;
  return std::chrono::duration_cast<std::chrono::milliseconds>(clock::now().time_since_epoch()).count();
}

bool porter_metrics_maybe_send(const SwmJob &job,
                               const PorterMetricsConfig &cfg,
                               PorterMetricsState *state,
                               int64_t now_ms) {
  if (cfg.sample_interval_ms <= 0 || cfg.report_interval_ms <= 0 || state == nullptr) {
    return true;
  }
  if (state->last_sample_ms != 0 && (now_ms - state->last_sample_ms) < cfg.sample_interval_ms) {
    return true;
  }
  if (state->window_start_ms == 0) {
    reset_window(state, now_ms);
  }

  bool have_cpu = false;
  bool have_mem = false;
  bool have_gpu = false;
  double cpu_percent = 0.0;
  uint64_t mem_bytes = 0;
  double gpu_util = 0.0;
  uint64_t gpu_mem = 0;
  take_sample(cfg, state, now_ms, &have_cpu, &cpu_percent, &have_mem, &mem_bytes, &have_gpu, &gpu_util, &gpu_mem);
  accumulate_sample(state, have_cpu, cpu_percent, have_mem, mem_bytes, have_gpu, gpu_util, gpu_mem);

  if ((now_ms - state->window_start_ms) >= cfg.report_interval_ms) {
    return flush_window(job, state, now_ms);
  }
  return true;
}

bool porter_metrics_flush(const SwmJob &job,
                          const PorterMetricsConfig &cfg,
                          PorterMetricsState *state,
                          int64_t now_ms) {
  if (cfg.sample_interval_ms <= 0 || cfg.report_interval_ms <= 0 || state == nullptr) {
    return true;
  }
  return flush_window(job, state, now_ms);
}

}  // namespace swm
