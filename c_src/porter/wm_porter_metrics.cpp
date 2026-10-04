#include "wm_porter_metrics.h"

#include "wm_io.h"

#include <dlfcn.h>
#include <ei.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace swm {
namespace {

namespace fs = std::filesystem;

// Minimal NVML types so we do not require CUDA headers at build time.
using nvmlReturn_t = int;
using nvmlDevice_t = void *;
constexpr nvmlReturn_t NVML_SUCCESS = 0;

struct NvmlUtilization {
  unsigned int gpu = 0;
  unsigned int memory = 0;
};

struct NvmlMemory {
  unsigned long long total = 0;
  unsigned long long free = 0;
  unsigned long long used = 0;
};

using NvmlInitFn = nvmlReturn_t (*)();
using NvmlShutdownFn = nvmlReturn_t (*)();
using NvmlDeviceGetCountFn = nvmlReturn_t (*)(unsigned int *);
using NvmlDeviceGetHandleByIndexFn = nvmlReturn_t (*)(unsigned int, nvmlDevice_t *);
using NvmlDeviceGetUtilizationRatesFn = nvmlReturn_t (*)(nvmlDevice_t, NvmlUtilization *);
using NvmlDeviceGetMemoryInfoFn = nvmlReturn_t (*)(nvmlDevice_t, NvmlMemory *);

struct DlHandle {
  void *p = nullptr;

  DlHandle() = default;
  explicit DlHandle(void *handle) : p(handle) {}
  ~DlHandle() {
    if (p != nullptr) {
      dlclose(p);
    }
  }
  DlHandle(const DlHandle &) = delete;
  DlHandle &operator=(const DlHandle &) = delete;
  DlHandle(DlHandle &&other) noexcept : p(std::exchange(other.p, nullptr)) {}
  DlHandle &operator=(DlHandle &&other) noexcept {
    if (this != &other) {
      if (p != nullptr) {
        dlclose(p);
      }
      p = std::exchange(other.p, nullptr);
    }
    return *this;
  }

  [[nodiscard]] explicit operator bool() const { return p != nullptr; }
};

template <typename Fn>
Fn load_sym(void *handle, std::string_view name) {
  return reinterpret_cast<Fn>(dlsym(handle, std::string(name).c_str()));
}

struct NvmlLib {
  DlHandle handle;
  NvmlInitFn init = nullptr;
  NvmlShutdownFn shutdown = nullptr;
  NvmlDeviceGetCountFn device_get_count = nullptr;
  NvmlDeviceGetHandleByIndexFn device_get_handle = nullptr;
  NvmlDeviceGetUtilizationRatesFn device_get_util = nullptr;
  NvmlDeviceGetMemoryInfoFn device_get_memory = nullptr;
  bool init_ok = false;
  bool load_attempted = false;
};

NvmlLib &nvml_lib() {
  static NvmlLib lib;
  return lib;
}

struct EiBuf {
  ei_x_buff x {};
  bool ok = false;

  EiBuf() { ok = (ei_x_new(&x) == 0); }
  ~EiBuf() {
    if (ok) {
      ei_x_free(&x);
    }
  }
  EiBuf(const EiBuf &) = delete;
  EiBuf &operator=(const EiBuf &) = delete;

  [[nodiscard]] explicit operator bool() const { return ok; }
};

[[nodiscard]] std::optional<std::string_view> env_value(const SwmJob &job, std::string_view key) {
  for (const auto &kv : job.get_env()) {
    if (kv.first == key) {
      return std::string_view(kv.second);
    }
  }
  return std::nullopt;
}

[[nodiscard]] std::optional<int64_t> parse_i64(std::string_view s) {
  if (s.empty()) {
    return std::nullopt;
  }
  int64_t value = 0;
  const auto *first = s.data();
  const auto *last = s.data() + s.size();
  const auto [ptr, ec] = std::from_chars(first, last, value);
  if (ec != std::errc {} || ptr != last) {
    return std::nullopt;
  }
  return value;
}

[[nodiscard]] bool file_readable(std::string_view path) {
  std::error_code ec;
  return fs::exists(std::string(path), ec) && !ec;
}

[[nodiscard]] bool is_cgroup_v2() {
  return file_readable("/sys/fs/cgroup/cgroup.controllers");
}

[[nodiscard]] std::string read_self_cgroup_v2_path() {
  std::ifstream in("/proc/self/cgroup");
  if (!in) {
    return {};
  }
  std::string line;
  while (std::getline(in, line)) {
    constexpr std::string_view kPrefix = "0::";
    if (std::string_view(line).substr(0, kPrefix.size()) != kPrefix) {
      continue;
    }
    std::string rel = line.substr(kPrefix.size());
    if (rel.empty()) {
      rel = "/";
    }
    if (rel.front() != '/') {
      rel.insert(rel.begin(), '/');
    }
    return std::string("/sys/fs/cgroup") + rel;
  }
  return {};
}

[[nodiscard]] std::optional<uint64_t> read_usage_usec(std::string_view cgroup_path) {
  std::ifstream in(std::string(cgroup_path) + "/cpu.stat");
  if (!in) {
    return std::nullopt;
  }
  std::string key;
  uint64_t val = 0;
  while (in >> key >> val) {
    if (key == "usage_usec") {
      return val;
    }
  }
  return std::nullopt;
}

[[nodiscard]] std::optional<uint64_t> read_memory_current(std::string_view cgroup_path) {
  std::ifstream in(std::string(cgroup_path) + "/memory.current");
  if (!in) {
    return std::nullopt;
  }
  uint64_t val = 0;
  in >> val;
  if (!in) {
    return std::nullopt;
  }
  return val;
}

[[nodiscard]] unsigned ncpus() {
  const long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n < 1 ? 1u : static_cast<unsigned>(n);
}

[[nodiscard]] std::string hostname_str() {
  std::array<char, 256> buf {};
  if (gethostname(buf.data(), buf.size()) != 0) {
    return "unknown";
  }
  buf.back() = '\0';
  return std::string(buf.data());
}

bool load_nvml() {
  NvmlLib &lib = nvml_lib();
  if (lib.load_attempted) {
    return lib.init_ok;
  }
  lib.load_attempted = true;

  constexpr std::array<std::string_view, 2> kCandidates = {"libnvidia-ml.so.1", "libnvidia-ml.so"};
  for (const auto name : kCandidates) {
    lib.handle = DlHandle(dlopen(std::string(name).c_str(), RTLD_LAZY | RTLD_LOCAL));
    if (lib.handle) {
      break;
    }
  }
  if (!lib.handle) {
    swm_logd("NVML not available: %s", dlerror());
    return false;
  }

  void *const h = lib.handle.p;
  lib.init = load_sym<NvmlInitFn>(h, "nvmlInit_v2");
  if (lib.init == nullptr) {
    lib.init = load_sym<NvmlInitFn>(h, "nvmlInit");
  }
  lib.shutdown = load_sym<NvmlShutdownFn>(h, "nvmlShutdown");
  lib.device_get_count = load_sym<NvmlDeviceGetCountFn>(h, "nvmlDeviceGetCount_v2");
  if (lib.device_get_count == nullptr) {
    lib.device_get_count = load_sym<NvmlDeviceGetCountFn>(h, "nvmlDeviceGetCount");
  }
  lib.device_get_handle = load_sym<NvmlDeviceGetHandleByIndexFn>(h, "nvmlDeviceGetHandleByIndex_v2");
  if (lib.device_get_handle == nullptr) {
    lib.device_get_handle = load_sym<NvmlDeviceGetHandleByIndexFn>(h, "nvmlDeviceGetHandleByIndex");
  }
  lib.device_get_util = load_sym<NvmlDeviceGetUtilizationRatesFn>(h, "nvmlDeviceGetUtilizationRates");
  lib.device_get_memory = load_sym<NvmlDeviceGetMemoryInfoFn>(h, "nvmlDeviceGetMemoryInfo");

  if (lib.init == nullptr || lib.device_get_count == nullptr || lib.device_get_handle == nullptr ||
      lib.device_get_util == nullptr || lib.device_get_memory == nullptr) {
    swm_logi("NVML symbols incomplete; GPU metrics disabled");
    lib.handle = DlHandle {};
    return false;
  }

  if (lib.init() != NVML_SUCCESS) {
    swm_logi("nvmlInit failed; GPU metrics disabled");
    lib.handle = DlHandle {};
    return false;
  }
  lib.init_ok = true;
  swm_logd("NVML loaded for job GPU metrics");
  return true;
}

struct GpuSample {
  double util_percent = 0.0;
  uint64_t mem_bytes = 0;
};

[[nodiscard]] std::optional<GpuSample> query_gpu_nvml() {
  if (!load_nvml()) {
    return std::nullopt;
  }
  NvmlLib &lib = nvml_lib();
  unsigned int count = 0;
  if (lib.device_get_count(&count) != NVML_SUCCESS || count == 0) {
    return std::nullopt;
  }

  double util_sum = 0.0;
  uint64_t mem_sum = 0;
  unsigned ok = 0;
  for (unsigned int i = 0; i < count; ++i) {
    nvmlDevice_t dev = nullptr;
    if (lib.device_get_handle(i, &dev) != NVML_SUCCESS) {
      continue;
    }
    NvmlUtilization util {};
    NvmlMemory mem {};
    if (lib.device_get_util(dev, &util) != NVML_SUCCESS || lib.device_get_memory(dev, &mem) != NVML_SUCCESS) {
      continue;
    }
    util_sum += static_cast<double>(util.gpu);
    mem_sum += static_cast<uint64_t>(mem.used);
    ++ok;
  }
  if (ok == 0) {
    return std::nullopt;
  }
  return GpuSample {util_sum / static_cast<double>(ok), mem_sum};
}

bool encode_atom(EiBuf &buf, std::string_view atom) {
  return ei_x_encode_atom(&buf.x, std::string(atom).c_str()) == 0;
}

bool encode_binary(EiBuf &buf, std::string_view s) {
  return ei_x_encode_binary(&buf.x, s.data(), static_cast<int>(s.size())) == 0;
}

bool encode_kv_binary(EiBuf &buf, std::string_view key, std::string_view value) {
  return encode_atom(buf, key) && encode_binary(buf, value);
}

bool encode_kv_i64(EiBuf &buf, std::string_view key, int64_t value) {
  return encode_atom(buf, key) && ei_x_encode_longlong(&buf.x, static_cast<long long>(value)) == 0;
}

bool encode_kv_u64(EiBuf &buf, std::string_view key, uint64_t value) {
  // ei_x_encode_ulong takes unsigned long; ei_x_encode_ulonglong takes EI_ULONGLONG.
  // Prefer ulonglong for full uint64_t range on all LP64/LLP64 hosts.
  return encode_atom(buf, key) && ei_x_encode_ulonglong(&buf.x, static_cast<unsigned long long>(value)) == 0;
}

bool encode_kv_double(EiBuf &buf, std::string_view key, double value) {
  return encode_atom(buf, key) && ei_x_encode_double(&buf.x, value) == 0;
}

bool send_aggregated_metrics(std::string_view job_id,
                             std::string_view node,
                             int64_t ts_ms,
                             const PorterMetricsWindow &window) {
  if (window.empty()) {
    return true;
  }

  const bool have_cpu = window.cpu_samples > 0;
  const bool have_mem = window.mem_samples > 0;
  const bool have_gpu = window.gpu_samples > 0;
  const double cpu_avg = have_cpu ? window.cpu_sum / static_cast<double>(window.cpu_samples) : 0.0;
  const uint64_t mem_avg =
      have_mem ? static_cast<uint64_t>(std::llround(window.mem_sum / static_cast<double>(window.mem_samples))) : 0;
  const double gpu_util_avg = have_gpu ? window.gpu_util_sum / static_cast<double>(window.gpu_samples) : 0.0;
  const uint64_t gpu_mem_avg =
      have_gpu ? static_cast<uint64_t>(std::llround(window.gpu_mem_sum / static_cast<double>(window.gpu_samples))) : 0;
  const int64_t window_ms = std::max<int64_t>(0, ts_ms - window.start_ms);

  EiBuf buf;
  if (!buf || ei_x_encode_version(&buf.x) != 0 || ei_x_encode_tuple_header(&buf.x, 2) != 0 ||
      !encode_atom(buf, "porter_metrics")) {
    return false;
  }

  size_t arity = 5;
  if (have_cpu) {
    arity += 2;
  }
  if (have_mem) {
    arity += 2;
  }
  if (have_gpu) {
    arity += 4;
  }
  if (ei_x_encode_map_header(&buf.x, arity) != 0) {
    return false;
  }

  if (!encode_kv_binary(buf, "job_id", job_id) || !encode_kv_binary(buf, "node", node) ||
      !encode_kv_i64(buf, "ts", ts_ms) || !encode_kv_u64(buf, "samples", window.samples) ||
      !encode_kv_i64(buf, "window_ms", window_ms)) {
    return false;
  }
  if (have_cpu &&
      (!encode_kv_double(buf, "cpu_percent", cpu_avg) || !encode_kv_double(buf, "cpu_percent_max", window.cpu_max))) {
    return false;
  }
  if (have_mem && (!encode_kv_u64(buf, "mem_bytes", mem_avg) || !encode_kv_u64(buf, "mem_bytes_max", window.mem_max))) {
    return false;
  }
  if (have_gpu && (!encode_kv_double(buf, "gpu_util_percent", gpu_util_avg) ||
                   !encode_kv_double(buf, "gpu_util_percent_max", window.gpu_util_max) ||
                   !encode_kv_u64(buf, "gpu_mem_bytes", gpu_mem_avg) ||
                   !encode_kv_u64(buf, "gpu_mem_bytes_max", window.gpu_mem_max))) {
    return false;
  }

  const size_t buf_bytes = static_cast<size_t>(buf.x.index);
  swm_write_exact(&std::cout, buf.x.buff, buf_bytes);
  std::cout << std::flush;
  return true;
}

void ensure_cgroup(PorterMetricsState &state) {
  if (state.cgroup_checked) {
    return;
  }
  state.cgroup_checked = true;
  state.cgroup_v2_ok = is_cgroup_v2();
  if (state.cgroup_v2_ok) {
    state.cgroup_path = read_self_cgroup_v2_path();
    if (state.cgroup_path.empty()) {
      state.cgroup_path = "/sys/fs/cgroup";
    }
  } else if (!state.warned_no_v2) {
    state.warned_no_v2 = true;
    swm_logi("cgroup v2 not available; skipping CPU/memory job metrics");
  }
}

[[nodiscard]] PorterMetricsSample take_sample(const PorterMetricsConfig &cfg,
                                              PorterMetricsState &state,
                                              int64_t now_ms) {
  PorterMetricsSample sample;
  ensure_cgroup(state);

  if (state.cgroup_v2_ok && !state.cgroup_path.empty()) {
    if (const auto usage_usec = read_usage_usec(state.cgroup_path)) {
      if (state.have_cpu_baseline && state.last_sample_ms > 0) {
        const int64_t dt_ms = now_ms - state.last_sample_ms;
        if (dt_ms > 0 && *usage_usec >= state.last_usage_usec) {
          const double dt_usec = static_cast<double>(dt_ms) * 1000.0;
          const double delta = static_cast<double>(*usage_usec - state.last_usage_usec);
          double cpu = 100.0 * delta / (dt_usec * static_cast<double>(ncpus()));
          if (cpu < 0.0) {
            cpu = 0.0;
          }
          sample.cpu_percent = cpu;
        }
      }
      state.last_usage_usec = *usage_usec;
      state.have_cpu_baseline = true;
    } else {
      swm_logd("Could not read %s/cpu.stat", state.cgroup_path.c_str());
    }

    if (const auto mem = read_memory_current(state.cgroup_path)) {
      sample.mem_bytes = *mem;
    } else {
      swm_logd("Could not read %s/memory.current", state.cgroup_path.c_str());
    }
  }

  if (cfg.collect_gpu) {
    if (const auto gpu = query_gpu_nvml()) {
      sample.gpu_util_percent = gpu->util_percent;
      sample.gpu_mem_bytes = gpu->mem_bytes;
    }
  }

  state.last_sample_ms = now_ms;
  return sample;
}

bool flush_window(const SwmJob &job, PorterMetricsState &state, int64_t now_ms) {
  if (state.window.empty()) {
    state.window.reset(now_ms);
    return true;
  }
  if (!send_aggregated_metrics(job.get_id(), hostname_str(), now_ms, state.window)) {
    swm_loge("Failed to send aggregated porter_metrics");
    return false;
  }
  swm_logd("Sent aggregated porter_metrics job=%s samples=%u window_ms=%lld",
           job.get_id().c_str(),
           state.window.samples,
           static_cast<long long>(now_ms - state.window.start_ms));
  state.window.reset(now_ms);
  return true;
}

}  // namespace

void PorterMetricsWindow::reset(int64_t now_ms) {
  *this = PorterMetricsWindow {};
  start_ms = now_ms;
}

void PorterMetricsWindow::add(const PorterMetricsSample &sample) {
  if (!sample.any()) {
    return;
  }
  ++samples;
  if (sample.cpu_percent) {
    cpu_sum += *sample.cpu_percent;
    if (cpu_samples == 0 || *sample.cpu_percent > cpu_max) {
      cpu_max = *sample.cpu_percent;
    }
    ++cpu_samples;
  }
  if (sample.mem_bytes) {
    mem_sum += static_cast<double>(*sample.mem_bytes);
    if (*sample.mem_bytes > mem_max) {
      mem_max = *sample.mem_bytes;
    }
    ++mem_samples;
  }
  if (sample.gpu_util_percent || sample.gpu_mem_bytes) {
    if (sample.gpu_util_percent) {
      gpu_util_sum += *sample.gpu_util_percent;
      if (gpu_samples == 0 || *sample.gpu_util_percent > gpu_util_max) {
        gpu_util_max = *sample.gpu_util_percent;
      }
    }
    if (sample.gpu_mem_bytes) {
      gpu_mem_sum += static_cast<double>(*sample.gpu_mem_bytes);
      if (*sample.gpu_mem_bytes > gpu_mem_max) {
        gpu_mem_max = *sample.gpu_mem_bytes;
      }
    }
    ++gpu_samples;
  }
}

bool PorterMetricsWindow::ready(int64_t now_ms, int64_t report_interval_ms) const {
  return report_interval_ms > 0 && start_ms > 0 && (now_ms - start_ms) >= report_interval_ms;
}

PorterMetricsConfig porter_metrics_config_from_job(const SwmJob &job) {
  PorterMetricsConfig cfg;
  if (const auto sample = env_value(job, "SWM_METRICS_INTERVAL_MS")) {
    if (const auto v = parse_i64(*sample)) {
      cfg.sample_interval_ms = *v;
    }
  }
  if (const auto report = env_value(job, "SWM_METRICS_REPORT_MS")) {
    if (const auto v = parse_i64(*report)) {
      cfg.report_interval_ms = *v;
    }
  }
  if (cfg.report_interval_ms > 0 && cfg.sample_interval_ms > cfg.report_interval_ms) {
    cfg.sample_interval_ms = cfg.report_interval_ms;
  }
  if (const auto gpu = env_value(job, "SWM_METRICS_GPU")) {
    cfg.collect_gpu = (*gpu == "1" || *gpu == "true" || *gpu == "yes");
  }
  return cfg;
}

int64_t porter_metrics_now_ms() {
  using clock = std::chrono::system_clock;
  return std::chrono::duration_cast<std::chrono::milliseconds>(clock::now().time_since_epoch()).count();
}

bool porter_metrics_maybe_send(const SwmJob &job,
                               const PorterMetricsConfig &cfg,
                               PorterMetricsState &state,
                               int64_t now_ms) {
  if (cfg.sample_interval_ms <= 0 || cfg.report_interval_ms <= 0) {
    return true;
  }
  if (state.last_sample_ms != 0 && (now_ms - state.last_sample_ms) < cfg.sample_interval_ms) {
    return true;
  }
  if (state.window.start_ms == 0) {
    state.window.reset(now_ms);
  }

  state.window.add(take_sample(cfg, state, now_ms));
  if (state.window.ready(now_ms, cfg.report_interval_ms)) {
    return flush_window(job, state, now_ms);
  }
  return true;
}

bool porter_metrics_flush(const SwmJob &job,
                          const PorterMetricsConfig &cfg,
                          PorterMetricsState &state,
                          int64_t now_ms) {
  if (cfg.sample_interval_ms <= 0 || cfg.report_interval_ms <= 0) {
    return true;
  }
  // Take a final sample even if the sample interval has not elapsed yet.
  if (state.window.start_ms == 0) {
    state.window.reset(now_ms);
  }
  state.window.add(take_sample(cfg, state, now_ms));
  return flush_window(job, state, now_ms);
}

}  // namespace swm
