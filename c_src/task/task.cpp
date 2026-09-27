// swm-task: start one task (workload chunk) on every node allocated to a job.
// Always asks SWM via Porter control relay to spawn one process/container per node.
// With --pmix: also start per-node swm-pmix and inject PMIX_* bootstrap env.

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace {

constexpr const char *ctrl_env_name = "SWM_PORTER_CTRL";

void print_usage(const char *prog) {
  std::cerr << "Usage: " << prog << " [--pmix] [--help] <command> [args...]\n"
            << "  Spawn the command once per allocated job node via Porter/SWM.\n\n"
            << "  --pmix   Also enable PMIx (per-node swm-pmix + PMIX_* env).\n"
            << "           Without --pmix, ranks still spawn on every node, without PMIx.\n";
}

int connect_porter_ctrl(const std::string &path) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
  sockaddr_un addr {};
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
  const char *ctrl = std::getenv(ctrl_env_name);
  if (!ctrl || !*ctrl) {
    std::cerr << "swm-task: " << ctrl_env_name
              << " is not set; Porter control relay is required inside job containers.\n";
    return 2;
  }
  int fd = connect_porter_ctrl(ctrl);
  if (fd < 0) {
    std::cerr << "swm-task: cannot connect to Porter control socket " << ctrl << ": " << std::strerror(errno) << "\n";
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

  // Always ask SWM (via Porter) to spawn one container/process per allocated node.
  // --pmix additionally starts swm-pmix and injects PMIX_* bootstrap env.
  return run_via_porter(pmix, cmd);
}
