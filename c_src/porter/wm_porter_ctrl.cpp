#include "wm_porter_ctrl.h"

#include "wm_io.h"

#include <ei.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <vector>

namespace swm {

namespace {

constexpr size_t porter_req_tuple_size = 4;

std::string make_ctrl_path() {
  const char *job = std::getenv("SWM_JOB_ID");
  std::string id = job && *job ? job : std::to_string(getpid());
  return "/tmp/swm-porter-ctrl-" + id + ".sock";
}

}  // namespace

std::string porter_ctrl_listen(int *listen_fd_out) {
  *listen_fd_out = -1;
  const std::string path = make_ctrl_path();
  unlink(path.c_str());

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    swm_loge("porter ctrl socket: %s", std::strerror(errno));
    return "";
  }

  sockaddr_un addr {};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) {
    close(fd);
    return "";
  }
  std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

  if (bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
    swm_loge("porter ctrl bind %s: %s", path.c_str(), std::strerror(errno));
    close(fd);
    return "";
  }
  chmod(path.c_str(), 0666);
  if (listen(fd, 4) < 0) {
    swm_loge("porter ctrl listen: %s", std::strerror(errno));
    close(fd);
    unlink(path.c_str());
    return "";
  }
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0) {
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  }
  *listen_fd_out = fd;
  swm_logi("Porter control socket: %s", path.c_str());
  return path;
}

int porter_ctrl_accept(int listen_fd) {
  if (listen_fd < 0) {
    return -1;
  }
  int cfd = accept(listen_fd, nullptr, nullptr);
  if (cfd < 0) {
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      swm_loge("porter ctrl accept: %s", std::strerror(errno));
    }
    return -1;
  }
  return cfd;
}

static std::string unescape_token(const std::string &in) {
  std::string out;
  out.reserve(in.size());
  for (size_t i = 0; i < in.size(); ++i) {
    if (in[i] == '\\' && i + 1 < in.size()) {
      out.push_back(in[++i]);
    } else {
      out.push_back(in[i]);
    }
  }
  return out;
}

bool porter_ctrl_parse_spawn(const std::string &line, bool *pmix_out, std::vector<std::string> *argv_out) {
  *pmix_out = false;
  argv_out->clear();
  if (line.rfind("SPAWN", 0) != 0) {
    return false;
  }
  size_t i = 5;
  while (i < line.size() && line[i] == ' ') {
    ++i;
  }
  std::string cur;
  auto flush = [&]() {
    if (!cur.empty()) {
      std::string tok = unescape_token(cur);
      if (tok == "--pmix") {
        *pmix_out = true;
      } else {
        argv_out->push_back(tok);
      }
      cur.clear();
    }
  };
  for (; i < line.size(); ++i) {
    if (line[i] == '\\' && i + 1 < line.size()) {
      cur.push_back('\\');
      cur.push_back(line[++i]);
    } else if (line[i] == ' ') {
      flush();
    } else {
      cur.push_back(line[i]);
    }
  }
  flush();
  return !argv_out->empty();
}

int send_porter_req(const std::string &ref, const char *method, bool pmix, const std::vector<std::string> &argv) {
  ei_x_buff x;
  if (ei_x_new(&x)) {
    return -1;
  }
  if (ei_x_encode_version(&x)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_tuple_header(&x, porter_req_tuple_size)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "porter_req")) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_binary(&x, ref.data(), ref.size())) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, method)) {
    ei_x_free(&x);
    return -1;
  }
  // Args as map: #{pmix => bool, cmd => [binary,...]}
  if (ei_x_encode_map_header(&x, 2)) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "pmix") || ei_x_encode_atom(&x, pmix ? "true" : "false")) {
    ei_x_free(&x);
    return -1;
  }
  if (ei_x_encode_atom(&x, "cmd")) {
    ei_x_free(&x);
    return -1;
  }
  if (argv.empty()) {
    if (ei_x_encode_empty_list(&x)) {
      ei_x_free(&x);
      return -1;
    }
  } else {
    if (ei_x_encode_list_header(&x, argv.size())) {
      ei_x_free(&x);
      return -1;
    }
    for (const auto &a : argv) {
      if (ei_x_encode_string(&x, a.c_str())) {
        ei_x_free(&x);
        return -1;
      }
    }
    if (ei_x_encode_empty_list(&x)) {
      ei_x_free(&x);
      return -1;
    }
  }

  const uint64_t buf_bytes = x.index;
  swm_write_exact(&std::cout, x.buff, buf_bytes);
  ei_x_free(&x);
  fflush(stdout);
  swm_logd("Sent porter_req method=%s ref=%s", method, ref.c_str());
  return 0;
}

bool porter_ctrl_write_line(int fd, const std::string &line) {
  std::string msg = line;
  if (msg.empty() || msg.back() != '\n') {
    msg.push_back('\n');
  }
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

}  // namespace swm
