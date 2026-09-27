// swm-task: start one task (workload chunk) on nodes allocated to a job.
// Without --pmix: exec the binary locally in this container.
// With --pmix: ask SWM via Porter control relay to start PMIx + one rank/node.

#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <unistd.h>
#include <vector>

#include <sys/socket.h>
#include <sys/un.h>

namespace {

constexpr const char *kCtrlEnv = "SWM_PORTER_CTRL";

void print_usage(const char *prog) {
  std::cerr << "Usage: " << prog << " [--pmix] [--help] <command> [args...]\n"
            << "  Start one task per allocated node.\n\n"
            << "  --pmix   Enable PMIx (disabled by default); asks SWM via Porter.\n"
            << "           Without --pmix the command is exec'd in container as-is.\n";
}

int connect_porter_ctrl(const std::string &path) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    close(fd);
    errno = ENAMETOOLONG;
    return -1;
  }
  std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);
  if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

bool write_all(int fd, const std::string &msg) {
  const char *p = msg.data();
  size_t left = msg.size();
  while (left > 0) {
    ssize_t n = write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
  return true;
}

bool read_line(int fd, std::string &out) {
  out.clear();
  char c = 0;
  while (true) {
    ssize_t n = read(fd, &c, 1);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    if (n == 0) {
      return !out.empty();
    }
    if (c == '\n') {
      return true;
    }
    out.push_back(c);
  }
}

int run_via_porter(bool pmix, const std::vector<std::string> &argv) {
  const char *ctrl = std::getenv(kCtrlEnv);
  if (!ctrl || !*ctrl) {
    std::cerr << "swm-task: " << kCtrlEnv
              << " is not set; Porter control relay is required inside job containers.\n";
    return 2;
  }
  int fd = connect_porter_ctrl(ctrl);
  if (fd < 0) {
    std::cerr << "swm-task: cannot connect to Porter control socket " << ctrl << ": "
              << std::strerror(errno) << "\n";
    return 2;
  }

  std::string req = "SPAWN";
  if (pmix) {
    req += " --pmix";
  }
  for (const auto &a : argv) {
    req.push_back(' ');
    // Escape spaces with backslash for a minimal argv encoding.
    for (char ch : a) {
      if (ch == ' ' || ch == '\\') {
        req.push_back('\\');
      }
      req.push_back(ch);
    }
  }
  req.push_back('\n');

  if (!write_all(fd, req)) {
    std::cerr << "swm-task: failed to write SPAWN to Porter\n";
    close(fd);
    return 2;
  }

  // Foreground: wait for DONE / ERR from Porter (relayed from SWM).
  std::string line;
  while (read_line(fd, line)) {
    if (line.rfind("OK ", 0) == 0) {
      continue;
    }
    if (line.rfind("DONE ", 0) == 0) {
      int code = 0;
      try {
        code = std::stoi(line.substr(5));
      } catch (...) {
        code = 1;
      }
      close(fd);
      return code;
    }
    if (line.rfind("ERR ", 0) == 0) {
      std::cerr << "swm-task: " << line.substr(4) << "\n";
      close(fd);
      return 1;
    }
  }
  std::cerr << "swm-task: Porter control connection closed unexpectedly\n";
  close(fd);
  return 1;
}

int exec_local(const std::vector<std::string> &argv) {
  if (argv.empty()) {
    std::cerr << "swm-task: missing command\n";
    return 2;
  }
  std::vector<char *> c_argv;
  c_argv.reserve(argv.size() + 1);
  for (const auto &a : argv) {
    c_argv.push_back(const_cast<char *>(a.c_str()));
  }
  c_argv.push_back(nullptr);
  execvp(c_argv[0], c_argv.data());
  std::cerr << "swm-task: execvp(" << argv[0] << ") failed: " << std::strerror(errno) << "\n";
  return 127;
}

}  // namespace

int main(int argc, char *argv[]) {
  bool pmix = false;
  std::vector<std::string> cmd;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "-h" || a == "--help") {
      print_usage(argv[0]);
      return 0;
    }
    if (a == "--pmix") {
      pmix = true;
      continue;
    }
    if (a.rfind("-", 0) == 0) {
      std::cerr << "swm-task: unknown option " << a << "\n";
      print_usage(argv[0]);
      return 2;
    }
    for (; i < argc; ++i) {
      cmd.emplace_back(argv[i]);
    }
    break;
  }

  if (cmd.empty()) {
    print_usage(argv[0]);
    return 2;
  }

  // Multi-node / PMIx always goes through Porter -> SWM.
  // Local plain exec only when --pmix is off and we are not requesting remote ranks.
  // Issue #9: without --pmix, run the binary as-is in this container.
  if (pmix) {
    return run_via_porter(true, cmd);
  }
  return exec_local(cmd);
}
