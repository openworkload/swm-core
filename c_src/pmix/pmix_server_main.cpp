// swm-pmix: per-node PMIx server host helper (no PRRTE).
// Owned/supervised by wm_pmix.erl. Links libpmix and registers host callbacks.
// Communicates with Erlang over stdio: line-oriented commands in, status out.
//
// Cross-node fence (Slurm-like): fence_nb emits FENCE_IN; wm_pmix allgathers
// contributions and replies with FENCE_OUT; we then invoke the modex callback.

#include <pmix.h>
#include <pmix_server.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

std::string g_job_id;
std::string g_nspace;
std::atomic<bool> g_running {true};
std::atomic<int> g_contrib_id {0};
std::atomic<uint64_t> g_fence_seq {1};

std::mutex g_io_mu;
std::mutex g_fence_mu;

struct PendingFence {
  pmix_modex_cbfunc_t cbfunc = nullptr;
  void *cbdata = nullptr;
  std::vector<char> local_data;
};

std::map<uint64_t, PendingFence> g_pending_fences;

// ---- base64 (no external deps) ----

constexpr char kB64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string b64_encode(const char *data, size_t len) {
  std::string out;
  out.reserve(((len + 2) / 3) * 4);
  size_t i = 0;
  while (i + 3 <= len) {
    const unsigned n = (static_cast<unsigned char>(data[i]) << 16) | (static_cast<unsigned char>(data[i + 1]) << 8) |
                       static_cast<unsigned char>(data[i + 2]);
    out.push_back(kB64[(n >> 18) & 63]);
    out.push_back(kB64[(n >> 12) & 63]);
    out.push_back(kB64[(n >> 6) & 63]);
    out.push_back(kB64[n & 63]);
    i += 3;
  }
  if (i < len) {
    unsigned n = static_cast<unsigned char>(data[i]) << 16;
    out.push_back(kB64[(n >> 18) & 63]);
    if (i + 1 < len) {
      n |= static_cast<unsigned char>(data[i + 1]) << 8;
      out.push_back(kB64[(n >> 12) & 63]);
      out.push_back(kB64[(n >> 6) & 63]);
      out.push_back('=');
    } else {
      out.push_back(kB64[(n >> 12) & 63]);
      out.push_back('=');
      out.push_back('=');
    }
  }
  return out;
}

int b64_val(char c) {
  if (c >= 'A' && c <= 'Z') {
    return c - 'A';
  }
  if (c >= 'a' && c <= 'z') {
    return c - 'a' + 26;
  }
  if (c >= '0' && c <= '9') {
    return c - '0' + 52;
  }
  if (c == '+') {
    return 62;
  }
  if (c == '/') {
    return 63;
  }
  return -1;
}

bool b64_decode(const std::string &in, std::vector<char> &out) {
  out.clear();
  out.reserve(in.size() * 3 / 4);
  int val = 0;
  int valb = -8;
  for (char c : in) {
    if (c == '=' || c == '\n' || c == '\r') {
      break;
    }
    const int d = b64_val(c);
    if (d < 0) {
      return false;
    }
    val = (val << 6) + d;
    valb += 6;
    if (valb >= 0) {
      out.push_back(static_cast<char>((val >> valb) & 0xFF));
      valb -= 8;
    }
  }
  return true;
}

void emit_line(const std::string &line) {
  std::lock_guard<std::mutex> lock(g_io_mu);
  std::cout << line << std::endl;
}

void release_fence_buf(void *cbdata) {
  delete[] static_cast<char *>(cbdata);
}

pmix_status_t connected(const pmix_proc_t * /*proc*/, void * /*server_object*/, pmix_op_cbfunc_t cbfunc, void *cbdata) {
  if (cbfunc) {
    cbfunc(PMIX_SUCCESS, cbdata);
  }
  return PMIX_SUCCESS;
}

pmix_status_t finalized(const pmix_proc_t * /*proc*/, void * /*server_object*/, pmix_op_cbfunc_t cbfunc, void *cbdata) {
  if (cbfunc) {
    cbfunc(PMIX_SUCCESS, cbdata);
  }
  return PMIX_SUCCESS;
}

pmix_status_t abort_fn(const pmix_proc_t * /*proc*/,
                       void * /*server_object*/,
                       int status,
                       const char msg[],
                       pmix_proc_t /*procs*/[],
                       size_t /*nprocs*/,
                       pmix_op_cbfunc_t cbfunc,
                       void *cbdata) {
  std::cerr << "swm-pmix: abort status=" << status << " msg=" << (msg ? msg : "") << "\n";
  if (cbfunc) {
    cbfunc(PMIX_SUCCESS, cbdata);
  }
  return PMIX_SUCCESS;
}

pmix_status_t fencenb(const pmix_proc_t /*procs*/[],
                      size_t /*nprocs*/,
                      const pmix_info_t /*info*/[],
                      size_t /*ninfo*/,
                      char *data,
                      size_t ndata,
                      pmix_modex_cbfunc_t cbfunc,
                      void *cbdata) {
  // Host must allgather across nodes via wm_pmix; do not complete locally.
  const uint64_t id = g_fence_seq.fetch_add(1);
  PendingFence pending;
  pending.cbfunc = cbfunc;
  pending.cbdata = cbdata;
  if (data != nullptr && ndata > 0) {
    pending.local_data.assign(data, data + ndata);
  }
  {
    std::lock_guard<std::mutex> lock(g_fence_mu);
    g_pending_fences[id] = std::move(pending);
  }

  const int contrib = g_contrib_id.load();
  const std::string b64 = (ndata > 0 && data != nullptr) ? b64_encode(data, ndata) : std::string();
  emit_line("FENCE_IN id=" + std::to_string(id) + " contrib=" + std::to_string(contrib) +
            " nbytes=" + std::to_string(ndata) + " b64=" + b64);
  return PMIX_SUCCESS;
}

void complete_fence(uint64_t id, pmix_status_t status, std::vector<char> &&blob) {
  PendingFence pending;
  {
    std::lock_guard<std::mutex> lock(g_fence_mu);
    auto it = g_pending_fences.find(id);
    if (it == g_pending_fences.end()) {
      std::cerr << "swm-pmix: FENCE_OUT for unknown id=" << id << "\n";
      return;
    }
    pending = std::move(it->second);
    g_pending_fences.erase(it);
  }
  if (!pending.cbfunc) {
    return;
  }
  if (status != PMIX_SUCCESS || blob.empty()) {
    pending.cbfunc(status, nullptr, 0, pending.cbdata, nullptr, nullptr);
    return;
  }
  char *buf = new char[blob.size()];
  std::memcpy(buf, blob.data(), blob.size());
  pending.cbfunc(status, buf, blob.size(), pending.cbdata, release_fence_buf, buf);
}

pmix_status_t dmodex(const pmix_proc_t * /*proc*/,
                     const pmix_info_t /*info*/[],
                     size_t /*ninfo*/,
                     pmix_modex_cbfunc_t cbfunc,
                     void *cbdata) {
  // After a collecting fence, clients usually already have peer data.
  // Direct modex across nodes is a follow-up; fail closed for now.
  if (cbfunc) {
    cbfunc(PMIX_ERR_NOT_FOUND, nullptr, 0, cbdata, nullptr, nullptr);
  }
  return PMIX_SUCCESS;
}

void print_usage(const char *prog) {
  std::cerr << "Usage: " << prog << " --job-id <id> [--nspace <name>]\n";
}

bool register_nspace(const std::string &nspace, size_t nprocs) {
  pmix_info_t *info = nullptr;
  size_t ninfo = 2;
  PMIX_INFO_CREATE(info, ninfo);
  uint32_t job_size = static_cast<uint32_t>(nprocs);
  uint32_t local = 1;
  PMIX_INFO_LOAD(&info[0], PMIX_JOB_SIZE, &job_size, PMIX_UINT32);
  PMIX_INFO_LOAD(&info[1], PMIX_LOCAL_SIZE, &local, PMIX_UINT32);

  pmix_status_t rc =
      PMIx_server_register_nspace(nspace.c_str(), static_cast<int>(nprocs), info, ninfo, nullptr, nullptr);
  PMIX_INFO_FREE(info, ninfo);
  return rc == PMIX_SUCCESS || rc == PMIX_OPERATION_SUCCEEDED;
}

struct ForkEnv {
  std::string uri;
  std::vector<std::pair<std::string, std::string>> vars;
};

ForkEnv server_fork_env(const std::string &nspace, pmix_rank_t rank) {
  ForkEnv out;
  pmix_proc_t proc;
  PMIX_PROC_LOAD(&proc, nspace.c_str(), rank);
  char **env = nullptr;
  pmix_status_t rc = PMIx_server_setup_fork(&proc, &env);
  if (rc == PMIX_SUCCESS && env != nullptr) {
    for (char **ep = env; *ep != nullptr; ++ep) {
      const char *eq = std::strchr(*ep, '=');
      if (eq == nullptr) {
        continue;
      }
      std::string key(*ep, eq - *ep);
      std::string val(eq + 1);
      if (key.rfind("PMIX_SERVER_URI", 0) == 0 && out.uri.empty()) {
        out.uri = val;
      }
      out.vars.emplace_back(std::move(key), std::move(val));
    }
    PMIX_ARGV_FREE(env);
  }
  if (!out.uri.empty()) {
    bool have = false;
    for (const auto &kv : out.vars) {
      if (kv.first == "PMIX_SERVER_URI") {
        have = true;
        break;
      }
    }
    if (!have) {
      out.vars.emplace_back("PMIX_SERVER_URI", out.uri);
    }
  }
  return out;
}

void chmod_tree_world_rx(const std::string &path) {
  const std::string cmd = "chmod -R a+rX " + path + " 2>/dev/null";
  std::system(cmd.c_str());
}

bool parse_kv_token(const std::string &line, const std::string &key, std::string &val) {
  const std::string prefix = key + "=";
  const size_t pos = line.find(prefix);
  if (pos == std::string::npos) {
    return false;
  }
  size_t start = pos + prefix.size();
  size_t end = line.find(' ', start);
  if (end == std::string::npos) {
    end = line.size();
  }
  // b64 may be the last field and contain no spaces (base64 alphabet).
  val = line.substr(start, end - start);
  return true;
}

void handle_fence_out(const std::string &line) {
  std::string id_s;
  std::string status_s;
  std::string nbytes_s;
  std::string b64;
  if (!parse_kv_token(line, "id", id_s) || !parse_kv_token(line, "status", status_s)) {
    std::cerr << "swm-pmix: bad FENCE_OUT: " << line << "\n";
    return;
  }
  parse_kv_token(line, "nbytes", nbytes_s);
  // b64= is last; take remainder after b64=
  const std::string b64key = "b64=";
  const size_t bpos = line.find(b64key);
  if (bpos != std::string::npos) {
    b64 = line.substr(bpos + b64key.size());
  }
  uint64_t id = 0;
  int status = PMIX_ERROR;
  try {
    id = std::stoull(id_s);
    status = std::stoi(status_s);
  } catch (...) {
    std::cerr << "swm-pmix: bad FENCE_OUT numbers\n";
    return;
  }
  std::vector<char> blob;
  if (!b64.empty() && !b64_decode(b64, blob)) {
    std::cerr << "swm-pmix: FENCE_OUT base64 decode failed id=" << id << "\n";
    complete_fence(id, PMIX_ERROR, {});
    return;
  }
  (void)nbytes_s;
  complete_fence(id, static_cast<pmix_status_t>(status), std::move(blob));
}

}  // namespace

int main(int argc, char *argv[]) {
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--job-id" && i + 1 < argc) {
      g_job_id = argv[++i];
    } else if (a == "--nspace" && i + 1 < argc) {
      g_nspace = argv[++i];
    } else if (a == "-h" || a == "--help") {
      print_usage(argv[0]);
      return 0;
    }
  }
  if (g_job_id.empty()) {
    const char *env = std::getenv("SWM_JOB_ID");
    if (env) {
      g_job_id = env;
    }
  }
  if (g_job_id.empty()) {
    print_usage(argv[0]);
    return 2;
  }
  if (g_nspace.empty()) {
    g_nspace = "swm-" + g_job_id;
  }

  pmix_server_module_t module;
  std::memset(&module, 0, sizeof(module));
  module.client_connected = connected;
  module.client_finalized = finalized;
  module.abort = abort_fn;
  module.fence_nb = fencenb;
  module.direct_modex = dmodex;

  pmix_info_t *info = nullptr;
  size_t ninfo = 1;
  PMIX_INFO_CREATE(info, ninfo);
  std::string tmpdir = "/tmp/swm-pmix-" + g_job_id;
  ::mkdir(tmpdir.c_str(), 0755);
  PMIX_INFO_LOAD(&info[0], PMIX_SERVER_TMPDIR, tmpdir.c_str(), PMIX_STRING);

  pmix_status_t rc = PMIx_server_init(&module, info, ninfo);
  PMIX_INFO_FREE(info, ninfo);
  if (rc != PMIX_SUCCESS) {
    std::cerr << "swm-pmix: PMIx_server_init failed: " << rc << "\n";
    return 1;
  }

  if (!register_nspace(g_nspace, 1)) {
    std::cerr << "swm-pmix: register_nspace warning (continuing)\n";
  }

  const ForkEnv fork_env = server_fork_env(g_nspace, 0);
  chmod_tree_world_rx(tmpdir);
  if (fork_env.uri.empty()) {
    std::cerr << "swm-pmix: warning: PMIX_SERVER_URI empty after setup_fork\n";
  }
  emit_line("READY nspace=" + g_nspace + " job=" + g_job_id + " uri=" + fork_env.uri);
  for (const auto &kv : fork_env.vars) {
    emit_line("ENV " + kv.first + "=" + kv.second);
  }
  emit_line("FORK_ENV_DONE");

  std::string line;
  while (g_running && std::getline(std::cin, line)) {
    if (line.rfind("REGISTER ", 0) == 0) {
      size_t nprocs = 1;
      try {
        nprocs = static_cast<size_t>(std::stoul(line.substr(9)));
      } catch (...) {
        nprocs = 1;
      }
      if (register_nspace(g_nspace, nprocs)) {
        emit_line("OK REGISTER " + std::to_string(nprocs));
      } else {
        emit_line("ERR REGISTER");
      }
    } else if (line.rfind("CONTRIB_ID ", 0) == 0) {
      try {
        g_contrib_id.store(std::stoi(line.substr(11)));
        emit_line("OK CONTRIB_ID " + std::to_string(g_contrib_id.load()));
      } catch (...) {
        emit_line("ERR CONTRIB_ID");
      }
    } else if (line.rfind("SETUP_FORK ", 0) == 0) {
      pmix_rank_t rank = 0;
      try {
        rank = static_cast<pmix_rank_t>(std::stoul(line.substr(11)));
      } catch (...) {
        rank = 0;
      }
      g_contrib_id.store(static_cast<int>(rank));
      const ForkEnv fe = server_fork_env(g_nspace, rank);
      chmod_tree_world_rx(tmpdir);
      emit_line("OK SETUP_FORK rank=" + std::to_string(rank) + " uri=" + fe.uri);
      for (const auto &kv : fe.vars) {
        emit_line("ENV " + kv.first + "=" + kv.second);
      }
      emit_line("FORK_ENV_DONE");
    } else if (line.rfind("FENCE_OUT ", 0) == 0) {
      handle_fence_out(line);
    } else if (line == "STOP") {
      g_running = false;
      break;
    } else if (line == "PING") {
      emit_line("PONG");
    }
  }

  {
    std::lock_guard<std::mutex> lock(g_fence_mu);
    for (auto &kv : g_pending_fences) {
      if (kv.second.cbfunc) {
        kv.second.cbfunc(PMIX_ERROR, nullptr, 0, kv.second.cbdata, nullptr, nullptr);
      }
    }
    g_pending_fences.clear();
  }

  PMIx_server_finalize();
  emit_line("STOPPED");
  return 0;
}
