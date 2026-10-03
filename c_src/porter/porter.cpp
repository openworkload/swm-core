#include "exitcodes.h"
#include "wm_entity.h"
#include "wm_io.h"
#include "wm_job.h"
#include "wm_porter_ctrl.h"
#include "wm_porter_data.h"
#include "wm_porter_metrics.h"
#include "wm_process.h"

#include <ei.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <linux/limits.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <vector>

#define CHILD_WAITING_TIME        5
#define PROCESS_TUPLE_SIZE        6
#define PORTER_COMMAND_CTRL_REPLY 2

using namespace swm;

void set_uid_gid(const uid_t uid, const uid_t gid) {
  int status = -1;
  status = setregid(gid, gid);
  if (status < 0) {
    swm_loge("Can't set gid, status=", status);
    exit(status);
  }
  status = setreuid(uid, uid);
  if (status < 0) {
    swm_loge("Can't set uid, status=", status);
    exit(status);
  }
  swm_logi("Current process new UID/GID: %d/%d", getuid(), getgid());
}

void set_workdir(passwd *pw, SwmJob &job) {
  auto workdir = job.get_workdir();
  if (workdir.empty()) {
    workdir = pw->pw_dir;
  }
  chdir(workdir.c_str());

  // Validate current working directory
  char cwd[PATH_MAX];
  if (getcwd(cwd, sizeof(cwd))) {
    swm_logi("Current working directory: %s", cwd);
  } else {
    perror("getcwd() error");
    exit(EXIT_SYSTEM_ERROR);
  }
}

void switch_stdout(const std::string &path) {
  // Append so concurrent rank Porters on a shared NFS workdir keep all output.
  FILE *outfile = fopen(path.c_str(), "a");
  if (!outfile) {
    swm_loge("Can't open %s", path.c_str());
    perror("Stdout file opening error");
    exit(EXIT_FILE_ERROR);
  }
  if (dup2(fileno(outfile), STDOUT_FILENO) < 0) {
    swm_loge("Can't duplicate out file descriptor for %s: %s", path.c_str(), std::strerror(errno));
    perror("Stderr file opening error");
    exit(EXIT_SYSTEM_ERROR);
  }
  fclose(outfile);
}

void switch_stderr(const std::string &path) {
  FILE *errfile = fopen(path.c_str(), "a");
  if (!errfile) {
    swm_loge("Can't open %s", path.c_str());
    exit(EXIT_FILE_ERROR);
  }
  if (dup2(fileno(errfile), STDERR_FILENO) < 0) {
    swm_loge("Can't duplicate err file descriptor for %s: %s", path.c_str(), std::strerror(errno));
    exit(EXIT_SYSTEM_ERROR);
  }
  fclose(errfile);
}

void set_io(const SwmJob &job) {
  swm_logd("Set IO");
  auto out_path = job.get_job_stdout();
  static std::string token = "%j";
  const auto id = job.get_id();
  const size_t len = std::string("%j").size();
  // Job script keeps stdout.log / stderr.log. Rank/task processes (SWM_PMIX_RANK
  // set) write separate files next to them: stdout-task<N>.log, stderr-task<N>.log
  // so concurrent NFS writers do not share one append stream.
  const char *task_num = std::getenv("SWM_PMIX_RANK");
  auto task_log_name = [task_num](std::string base) {
    if (!task_num || task_num[0] == '\0') {
      return base;
    }
    const auto dot = base.rfind('.');
    if (dot == std::string::npos) {
      return base + "-task" + task_num;
    }
    return base.substr(0, dot) + "-task" + task_num + base.substr(dot);
  };
  if (out_path.size()) {
    const size_t pos = out_path.find(token);
    if (pos != std::string::npos) {
      out_path.replace(pos, len, id);
    }
    out_path = task_log_name(std::move(out_path));
    swm_logi("Job stdout: %s", out_path.c_str());
    switch_stdout(out_path);
  }

  auto err_path = job.get_job_stderr();
  if (err_path.size()) {
    const size_t pos = err_path.find(token);
    if (pos != std::string::npos) {
      err_path.replace(pos, len, id);
    }
    err_path = task_log_name(std::move(err_path));
    swm_logi("Job stderr: %s", err_path.c_str());
    switch_stderr(err_path);
  }
}

void print_usage(const std::string &prog) {
  std::cout << "Usage: " << prog << " [-d|-h]" << std::endl;
}

void parse_opts(int argc, char *const argv[]) {
  const char *short_opts = "hd";
  const option long_opts[] = {
      {"help", no_argument, nullptr, 'h'}, {"debug", no_argument, nullptr, 'd'}, {nullptr, 0, nullptr, 0}};

  int res;
  int opt_idx;
  int log_level = SWM_LOG_LEVEL_INFO;
  while ((res = getopt_long(argc, argv, short_opts, long_opts, &opt_idx)) != -1) {
    switch (res) {
      case 'h': {
        print_usage(argv[0]);
        exit(0);
      };
      case 'd': {
        log_level = SWM_LOG_LEVEL_DEBUG1;
      };
      default: {
      }
    }
  }
  swm_log_init(log_level, stderr);
}

std::string join_csv(const std::vector<std::string> &items) {
  std::string out;
  for (size_t i = 0; i < items.size(); ++i) {
    if (i) {
      out += ',';
    }
    out += items[i];
  }
  return out;
}

std::string ports_from_request(const SwmJob &job) {
  for (const auto &resource : job.get_request()) {
    if (resource.get_name() != "ports") {
      continue;
    }
    for (const auto &prop : resource.get_properties()) {
      if (prop.first != "value") {
        continue;
      }
      std::string value;
      int index = 0;
      ei_x_buff buf = prop.second;
      if (buf.buff && ei_buffer_to_str(buf.buff, index, value) == 0) {
        return value;
      }
    }
  }
  return "";
}

// Directories prepended to PATH so job scripts find swm-task / swm-porter / etc.
std::vector<std::string> swm_path_dirs() {
  std::vector<std::string> dirs;
  dirs.emplace_back("/opt/swm/current/bin");

  char buf[PATH_MAX];
  const ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n > 0) {
    buf[n] = '\0';
    std::string exe(buf);
    const auto slash = exe.rfind('/');
    if (slash != std::string::npos && slash > 0) {
      const std::string exe_dir = exe.substr(0, slash);
      if (exe_dir != dirs.front()) {
        dirs.push_back(exe_dir);
      }
    }
  }
  return dirs;
}

void set_env(passwd *pw, const SwmJob &job, const std::string &ctrl_path) {
  const std::string cwd = job.get_workdir();
  setenv("HOME", pw->pw_dir, 1);
  setenv("USER", pw->pw_name, 1);

  // User-defined job.env first; SWM_* exports below overwrite on conflict.
  for (const auto &kv : job.get_env()) {
    if (!kv.first.empty()) {
      setenv(kv.first.c_str(), kv.second.c_str(), 1);
    }
  }

  setenv("SWM_JOB_ID", job.get_id().c_str(), 1);
  setenv("SWM_JOB_NAME", job.get_name().c_str(), 1);
  // Account name is resolved in Erlang (prepare_porter_input) into account_id for porter.
  setenv("SWM_JOB_ACCOUNT", job.get_account_id().c_str(), 1);
  const auto nodes = job.get_nodes();
  const auto nodes_csv = join_csv(nodes);
  const auto nodes_number = std::to_string(nodes.size());
  setenv("SWM_JOB_NODES", nodes_csv.c_str(), 1);
  setenv("SWM_JOB_NODES_NUMBER", nodes_number.c_str(), 1);
  setenv("SWM_JOB_COMMENT", job.get_comment().c_str(), 1);
  const auto input_files = join_csv(job.get_input_files());
  const auto output_files = join_csv(job.get_output_files());
  setenv("SWM_JOB_INPUT_FILES", input_files.c_str(), 1);
  setenv("SWM_JOB_OUTPUT_FILES", output_files.c_str(), 1);
  const auto ports = ports_from_request(job);
  setenv("SWM_JOB_PORTS", ports.c_str(), 1);
  setenv("SWM_RELOCATABLE", job.get_relocatable() == "true" ? "YES" : "NO", 1);
  setenv("SWM_KEEP_RESOURCES", job.get_keep_resources() == "true" ? "YES" : "NO", 1);
  if (!ctrl_path.empty()) {
    setenv("SWM_PORTER_CTRL", ctrl_path.c_str(), 1);
  }

  // workdir : /opt/swm/current/bin [: porter dir] : inherited PATH
  const char *old_path = getenv("PATH");
  std::string path;
  if (!cwd.empty()) {
    path = cwd;
  }
  for (const auto &dir : swm_path_dirs()) {
    if (!path.empty()) {
      path += ":";
    }
    path += dir;
  }
  if (old_path != nullptr && old_path[0] != '\0') {
    if (!path.empty()) {
      path += ":";
    }
    path += old_path;
  }
  setenv("PATH", path.c_str(), 1);
  if (!cwd.empty()) {
    setenv("PWD", cwd.c_str(), 1);
  }
  swm_logi("Job PATH=%s", path.c_str());
}

int send_process_info(const SwmProcess &proc) {
  ei_x_buff x;
  if (ei_x_new(&x)) {
    swm_loge("Can't create new process term");
    return -1;
  }
  if (ei_x_encode_version(&x)) {
    swm_loge("Can't encode version");
    return -1;
  }
  if (ei_x_encode_tuple_header(&x, PROCESS_TUPLE_SIZE)) {
    swm_loge("Can't encode process tuple header");
    return -1;
  }
  if (ei_x_encode_atom(&x, "process")) {
    swm_loge("Can't encode process first atom");
    return -1;
  }
  if (ei_x_encode_ulong(&x, proc.get_pid())) {
    swm_loge("Can't encode process pid");
    return -1;
  }
  if (ei_x_encode_string(&x, proc.get_state().c_str())) {
    swm_loge("Can't encode process state");
    return -1;
  }
  if (ei_x_encode_long(&x, proc.get_exitcode())) {
    swm_loge("Can't encode process exitcode");
    return -1;
  }
  if (ei_x_encode_long(&x, proc.get_signal())) {
    swm_loge("Can't encode process signal");
    return -1;
  }
  if (ei_x_encode_string(&x, proc.get_comment().c_str())) {
    swm_loge("Can't encode process comment");
    return -1;
  }

  if (swm_get_log_level() >= SWM_LOG_LEVEL_DEBUG1) {
    char *term_str = nullptr;
    int index = 0;
    ei_s_print_term(&term_str, x.buff, &index);
    swm_logd("Process term: ", term_str);
    // ei_s_print_term allocates with malloc(); must free(), not delete[].
    free(term_str);
  }

  const uint64_t buf_bytes = x.index;
  swm_write_exact(&std::cout, x.buff, buf_bytes);
  if (ei_x_free(&x)) {
    swm_loge("Can't free encoded buffer for process term");
  }
  fflush(stdout);

  swm_logd("Process info has been just sent to stdout (%s)", proc.get_state().c_str());
  return 0;
}

std::string save_script(const SwmJob &job, const uid_t uid, const gid_t gid, const std::string &content) {
  // Prefer container name over pid: rank Porters can share the same host pid
  // namespace view (e.g. both pid 2) when /tmp is bind-mounted across containers.
  const auto job_id = job.get_id();
  std::string tag = job.get_container();
  if (tag.empty()) {
    tag = "pid" + std::to_string(getpid());
  }
  for (char &c : tag) {
    if (c == '/' || c == ' ') {
      c = '-';
    }
  }
  const std::string path = "/tmp/swm-" + job_id + "-" + tag + ".sh";
  std::ofstream file(path, std::ofstream::out);
  if (!file.is_open()) {
    const auto msg = "Error creating script file: " + path;
    std::perror(msg.c_str());
    exit(EXIT_FAILURE);
  }
  file << content;
  file.close();

  if (chmod(path.c_str(), S_IRWXU) != 0) {
    const auto msg = "Could not set permissions to " + path;
    std::perror(msg.c_str());
    exit(EXIT_FAILURE);
  }

  if (chown(path.c_str(), uid, gid) == -1) {
    const auto msg = "Could not set ownership to " + path;
    std::perror(msg.c_str());
    exit(EXIT_FAILURE);
  }

  return path;
}

void set_job_dir_ownership(const SwmJob &job, const uid_t uid, const gid_t gid) {
  const auto workdir = job.get_workdir();
  if (chown(workdir.c_str(), uid, gid) == -1) {
    const std::string msg = "Could not chown directory " + workdir;
    std::perror(msg.c_str());
    exit(EXIT_FAILURE);
  }
}

int main(int argc, char *const argv[]) {
  swm_logd("Porter has started");

  parse_opts(argc, argv);
  ei_init();

  byte *data[SWM_DATA_TYPES_COUNT];
  if (get_porter_data(&std::cin, data)) {
    swm_loge("Could not read raw input data");
    return EXIT_FAILURE;
  }

  SwmProcInfo info;
  if (parse_data(data, info)) {
    swm_loge("Could not decode data");
    return EXIT_FAILURE;
  }

  for (size_t i = 0; i < SWM_DATA_TYPES_COUNT; i++) {
    delete[] data[i];
  }

  pid_t child_pid;

  int ctrl_listen = -1;
  setenv("SWM_JOB_ID", info.job.get_id().c_str(), 1);
  const std::string ctrl_path = porter_ctrl_listen(&ctrl_listen);

  if ((child_pid = fork()) == -1) {
    swm_loge("Fork error!");
    exit(EXIT_FAILURE);
  } else if (child_pid == 0) { /* This is the child */
    if (ctrl_listen >= 0) {
      close(ctrl_listen);
    }
    const auto username = info.user.get_name().c_str();
    swm_logi("Job process forked (UID=%d), user name: \"%s\"", getuid(), username);

    size_t counter = 0;
    const uint64_t max_attempts = 20;
    passwd *pw = nullptr;
    while ((pw = getpwnam(username)) == nullptr) {
      if (++counter >= max_attempts) {
        swm_logd("User \"%s\" not found after %d attempts => exit", username, max_attempts);
        exit(EXIT_USER_NOT_FOUND);
      }
      swm_logd("User \"%s\" not found (yet) => wait and repeat", username);
      sleep(1);
    };
    swm_logd("User \"%s\" found: uid=%d gid=%d", username, pw->pw_uid, pw->pw_gid);

    const auto content = info.job.get_script_content();
    const auto path = save_script(info.job, pw->pw_uid, pw->pw_gid, content);
    swm_logi("Temporary execution path: \"%s\"", path.c_str());

    set_job_dir_ownership(info.job, pw->pw_uid, pw->pw_gid);
    set_uid_gid(pw->pw_uid, pw->pw_gid);
    set_env(pw, info.job, ctrl_path);
    set_workdir(pw, info.job);

    set_io(info.job);  // do not use logger after this point

    extern char **environ;
    char *const argv[] = {
        const_cast<char *>("/bin/sh"), const_cast<char *>("-c"), const_cast<char *>(path.c_str()), nullptr};
    execve("/bin/sh", &argv[0], environ);

  } else { /* This is the parent */
    swm_logi("Parent process started, job process PID=%d", child_pid);

    const PorterMetricsConfig metrics_cfg = porter_metrics_config_from_job(info.job);
    PorterMetricsState metrics_state;
    if (metrics_cfg.sample_interval_ms > 0 && metrics_cfg.report_interval_ms > 0) {
      swm_logi("Job metrics sample=%lld ms report=%lld ms gpu=%d",
               static_cast<long long>(metrics_cfg.sample_interval_ms),
               static_cast<long long>(metrics_cfg.report_interval_ms),
               metrics_cfg.collect_gpu ? 1 : 0);
    }

    // Non-blocking stdin for control replies from SWM.
    {
      int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
      if (flags >= 0) {
        fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
      }
    }

    int status = 0;
    int ctrl_client = -1;
    std::string ctrl_buf;
    std::map<std::string, int> pending_refs;  // ref -> client fd

    auto make_ref = []() {
      return std::to_string(getpid()) + "-" + std::to_string(time(nullptr)) + "-" + std::to_string(rand());
    };

    auto handle_ctrl_line = [&](const std::string &line) {
      bool pmix = false;
      std::vector<std::string> argv;
      if (!porter_ctrl_parse_spawn(line, &pmix, &argv)) {
        if (ctrl_client >= 0) {
          porter_ctrl_write_line(ctrl_client, "ERR bad SPAWN line");
        }
        return;
      }
      const std::string ref = make_ref();
      pending_refs[ref] = ctrl_client;
      if (send_porter_req(ref, "spawn_task", pmix, argv)) {
        porter_ctrl_write_line(ctrl_client, "ERR relay failed");
        pending_refs.erase(ref);
      }
    };

    auto try_read_ctrl_client = [&]() {
      if (ctrl_client < 0) {
        return;
      }
      char tmp[512];
      ssize_t n = read(ctrl_client, tmp, sizeof(tmp));
      if (n < 0) {
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
          close(ctrl_client);
          ctrl_client = -1;
        }
        return;
      }
      if (n == 0) {
        close(ctrl_client);
        ctrl_client = -1;
        return;
      }
      ctrl_buf.append(tmp, static_cast<size_t>(n));
      size_t pos;
      while ((pos = ctrl_buf.find('\n')) != std::string::npos) {
        std::string line = ctrl_buf.substr(0, pos);
        ctrl_buf.erase(0, pos + 1);
        handle_ctrl_line(line);
      }
    };

    auto try_read_stdin_reply = [&]() {
      // Format: <<CMD=2, Size:32/big, TermBin>>
      unsigned char hdr[5];
      ssize_t n = read(STDIN_FILENO, hdr, 1);
      if (n <= 0) {
        return;
      }
      if (hdr[0] != PORTER_COMMAND_CTRL_REPLY) {
        swm_loge("Unexpected stdin command after RUN: %d", static_cast<int>(hdr[0]));
        // Drain rest poorly; skip
        return;
      }
      n = read(STDIN_FILENO, hdr + 1, 4);
      if (n != 4) {
        return;
      }
      uint32_t len = (uint32_t(hdr[1]) << 24) | (uint32_t(hdr[2]) << 16) | (uint32_t(hdr[3]) << 8) | uint32_t(hdr[4]);
      if (len == 0 || len > 16 * 1024 * 1024) {
        return;
      }
      std::vector<char> buf(len);
      size_t got = 0;
      while (got < len) {
        ssize_t r = read(STDIN_FILENO, buf.data() + got, len - got);
        if (r <= 0) {
          if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            usleep(10000);
            continue;
          }
          return;
        }
        got += static_cast<size_t>(r);
      }
      // Decode {porter_rep, RefBin, Msg}
      int index = 0;
      int version = 0;
      if (ei_decode_version(buf.data(), &index, &version) < 0) {
        return;
      }
      int arity = 0;
      if (ei_decode_tuple_header(buf.data(), &index, &arity) < 0 || arity < 3) {
        return;
      }
      char atom[64];
      if (ei_decode_atom(buf.data(), &index, atom) < 0) {
        return;
      }
      int bin_size = 0;
      int type = 0;
      long ignored = 0;
      if (ei_get_type(buf.data(), &index, &type, &bin_size) < 0) {
        return;
      }
      std::vector<char> refbuf(static_cast<size_t>(bin_size) + 1, 0);
      if (type == ERL_BINARY_EXT || type == ERL_STRING_EXT) {
        if (type == ERL_BINARY_EXT) {
          long sz = 0;
          if (ei_decode_binary(buf.data(), &index, refbuf.data(), &sz) < 0) {
            return;
          }
          refbuf[static_cast<size_t>(sz)] = 0;
        } else {
          if (ei_decode_string(buf.data(), &index, refbuf.data()) < 0) {
            return;
          }
        }
      } else {
        return;
      }
      std::string ref(refbuf.data());
      auto it = pending_refs.find(ref);
      if (it == pending_refs.end()) {
        swm_logd("No pending ctrl client for ref %s", ref.c_str());
        return;
      }
      int cfd = it->second;
      // Peek Msg: atom done | ok | error | tuple
      int mtype = 0;
      int msize = 0;
      if (ei_get_type(buf.data(), &index, &mtype, &msize) < 0) {
        return;
      }
      if (mtype == ERL_ATOM_EXT || mtype == ERL_ATOM_UTF8_EXT || mtype == ERL_SMALL_ATOM_EXT ||
          mtype == ERL_SMALL_ATOM_UTF8_EXT) {
        char matom[256];
        if (ei_decode_atom(buf.data(), &index, matom) == 0) {
          if (std::strcmp(matom, "ok") == 0 || std::string(matom).find("ok") == 0) {
            // might be bare ok -- treat as OK
            porter_ctrl_write_line(cfd, std::string("OK ") + ref);
          }
        }
      } else if (mtype == ERL_SMALL_TUPLE_EXT || mtype == ERL_LARGE_TUPLE_EXT) {
        int tarity = 0;
        int idx2 = index;
        if (ei_decode_tuple_header(buf.data(), &idx2, &tarity) == 0 && tarity >= 1) {
          char tag[64];
          if (ei_decode_atom(buf.data(), &idx2, tag) == 0) {
            if (std::strcmp(tag, "done") == 0 && tarity >= 2) {
              long code = 1;
              ei_decode_long(buf.data(), &idx2, &code);
              porter_ctrl_write_line(cfd, "DONE " + std::to_string(code));
              pending_refs.erase(it);
              if (cfd == ctrl_client) {
                // keep connection for simplicity
              }
            } else if (std::strcmp(tag, "ok") == 0) {
              porter_ctrl_write_line(cfd, std::string("OK ") + ref);
            } else if (std::strcmp(tag, "error") == 0) {
              porter_ctrl_write_line(cfd, "ERR task failed");
              pending_refs.erase(it);
            }
          }
        }
      }
      (void)ignored;
    };

    while (1) {
      // Accept new control clients
      if (ctrl_listen >= 0 && ctrl_client < 0) {
        int cfd = porter_ctrl_accept(ctrl_listen);
        if (cfd >= 0) {
          int flags = fcntl(cfd, F_GETFL, 0);
          if (flags >= 0) {
            fcntl(cfd, F_SETFL, flags | O_NONBLOCK);
          }
          ctrl_client = cfd;
          ctrl_buf.clear();
        }
      }
      try_read_ctrl_client();
      try_read_stdin_reply();

      pid_t end_pid = waitpid(child_pid, &status, WNOHANG | WUNTRACED);
      SwmProcess proc;
      proc.set_pid(child_pid);
      proc.set_state(SWM_JOB_STATE_ERROR);
      proc.set_exitcode(-1);
      proc.set_signal(-1);

      swm_logd("Child end_pid: %d (status=%d)", end_pid, status);
      if (end_pid == -1) { /*  error calling waitpid */
        swm_loge("waitpid error");
        proc.set_comment("waitpid error");
        if (send_process_info(proc)) {
          swm_loge("Process info not sent");
          return EXIT_FAILURE;
        }
        sleep(CHILD_WAITING_TIME);  // give container time to propagate the final info to swm
        exit(EXIT_FAILURE);
      } else if (end_pid == 0) { /* child still running  */
        proc.set_state(SWM_JOB_STATE_RUNNING);
        if (send_process_info(proc)) {
          swm_loge("Child process info not sent");
          return EXIT_FAILURE;
        }
        if (!porter_metrics_maybe_send(info.job, metrics_cfg, metrics_state, porter_metrics_now_ms())) {
          swm_loge("Job metrics not sent");
          return EXIT_FAILURE;
        }
        // Short sleep so control I/O stays responsive
        usleep(200000);
      } else if (end_pid == child_pid) { /* child ended */
        int exitcode = -1;
        int sig = 0;
        if (WIFEXITED(status)) {
          exitcode = WEXITSTATUS(status);
        }
        if (WIFSIGNALED(status)) {
          sig = WTERMSIG(status);
        }
        if (WIFSTOPPED(status)) {
          sig = WSTOPSIG(status);
        }
        // Send final status first so a logging failure cannot leave the job stuck in R.
        proc.set_state(SWM_JOB_STATE_FINISHED);
        proc.set_exitcode(exitcode);
        proc.set_signal(sig);
        if (send_process_info(proc)) {
          swm_loge("The final job process info has not been sent");
          return EXIT_FAILURE;
        }
        if (!porter_metrics_flush(info.job, metrics_cfg, metrics_state, porter_metrics_now_ms())) {
          swm_loge("Final job metrics flush failed");
        }
        if (WIFEXITED(status)) {
          if (exitcode == 0) {
            swm_logi("Job process has terminated normally (exit=%d)", exitcode);
          } else {
            swm_loge("Job process has terminated with exit code %d", exitcode);
          }
        }
        if (WIFSIGNALED(status)) {
          const char *strsig = strsignal(sig);
          swm_loge("Job process has terminated by uncaught signal \"%s\"", strsig);
          if (WCOREDUMP(status)) {
            swm_logi("Job process has produced a core dump");
          }
        }
        if (WIFSTOPPED(status)) {
          const char *strsig = strsignal(sig);
          swm_loge("Job process has been stopped by delivery of a signal \"%s\"", strsig);
        }
        sleep(CHILD_WAITING_TIME);  // give container time to propagate the final info to swm
        break;
      }
    }
    if (ctrl_client >= 0) {
      close(ctrl_client);
    }
    if (ctrl_listen >= 0) {
      close(ctrl_listen);
      unlink(ctrl_path.c_str());
    }
    wait(&status);
  }

  return EXIT_SUCCESS;
}
