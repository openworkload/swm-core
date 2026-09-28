// swm-pmix: per-node PMIx server host helper (no PRRTE).
// Owned/supervised by wm_pmix.erl. Links libpmix and registers host callbacks.
// Communicates with Erlang over stdio: line-oriented commands in, status out.

#include <pmix.h>
#include <pmix_server.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace {

std::string g_job_id;
std::string g_nspace;
std::atomic<bool> g_running {true};
std::mutex g_fence_mu;

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
                      char * /*data*/,
                      size_t /*ndata*/,
                      pmix_modex_cbfunc_t cbfunc,
                      void *cbdata) {
  // v1: local fence completes immediately (one rank/node). Cross-node fence
  // coordination can be added via wm_pmix later.
  std::lock_guard<std::mutex> lock(g_fence_mu);
  if (cbfunc) {
    cbfunc(PMIX_SUCCESS, nullptr, 0, cbdata, nullptr, nullptr);
  }
  return PMIX_SUCCESS;
}

pmix_status_t dmodex(const pmix_proc_t * /*proc*/,
                     const pmix_info_t /*info*/[],
                     size_t /*ninfo*/,
                     pmix_modex_cbfunc_t cbfunc,
                     void *cbdata) {
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

// Ask libpmix for client rendezvous env (URI is versioned: PMIX_SERVER_URI41, etc.).
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
  // Unversioned alias for clients that look for PMIX_SERVER_URI.
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
  // Rank containers bind /tmp and run as the job user; dstore defaults to 0750.
  const std::string cmd = "chmod -R a+rX " + path + " 2>/dev/null";
  std::system(cmd.c_str());
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
  // Rank containers bind-mount /tmp and run as the job user; allow traverse.
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

  // setup_fork materializes rendezvous URI + dstore paths for clients (MPI/PMIx).
  const ForkEnv fork_env = server_fork_env(g_nspace, 0);
  chmod_tree_world_rx(tmpdir);
  if (fork_env.uri.empty()) {
    std::cerr << "swm-pmix: warning: PMIX_SERVER_URI empty after setup_fork\n";
  }
  std::cout << "READY nspace=" << g_nspace << " job=" << g_job_id << " uri=" << fork_env.uri << std::endl;
  for (const auto &kv : fork_env.vars) {
    std::cout << "ENV " << kv.first << "=" << kv.second << std::endl;
  }
  std::cout << "FORK_ENV_DONE" << std::endl;

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
        std::cout << "OK REGISTER " << nprocs << std::endl;
      } else {
        std::cout << "ERR REGISTER" << std::endl;
      }
    } else if (line.rfind("SETUP_FORK ", 0) == 0) {
      pmix_rank_t rank = 0;
      try {
        rank = static_cast<pmix_rank_t>(std::stoul(line.substr(11)));
      } catch (...) {
        rank = 0;
      }
      const ForkEnv fe = server_fork_env(g_nspace, rank);
      chmod_tree_world_rx(tmpdir);
      std::cout << "OK SETUP_FORK rank=" << rank << " uri=" << fe.uri << std::endl;
      for (const auto &kv : fe.vars) {
        std::cout << "ENV " << kv.first << "=" << kv.second << std::endl;
      }
      std::cout << "FORK_ENV_DONE" << std::endl;
    } else if (line == "STOP") {
      g_running = false;
      break;
    } else if (line == "PING") {
      std::cout << "PONG" << std::endl;
    }
  }

  PMIx_server_finalize();
  std::cout << "STOPPED" << std::endl;
  return 0;
}
