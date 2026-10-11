#include "wm_safe_file.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>

namespace swm {

std::string job_runtime_dir(const std::string &job_id) {
  if (job_id.empty()) {
    return "";
  }
  const char *spool = std::getenv("SWM_SPOOL");
  if (spool == nullptr || spool[0] == '\0') {
    return "";
  }
  std::string base(spool);
  while (!base.empty() && base.back() == '/') {
    base.pop_back();
  }
  return base + "/job/" + job_id;
}

bool ensure_private_dir(const std::string &dir, uid_t uid, gid_t gid) {
  if (dir.empty() || dir == "/") {
    return false;
  }

  std::string cur;
  size_t pos = 0;
  if (dir[0] == '/') {
    cur = "/";
    pos = 1;
  }
  while (pos <= dir.size()) {
    const size_t slash = dir.find('/', pos);
    const std::string part = dir.substr(pos, slash == std::string::npos ? std::string::npos : slash - pos);
    if (!part.empty()) {
      if (cur != "/" && !cur.empty() && cur.back() != '/') {
        cur.push_back('/');
      }
      cur += part;
      if (mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) {
        return false;
      }
    }
    if (slash == std::string::npos) {
      break;
    }
    pos = slash + 1;
  }

  if (chmod(dir.c_str(), 0700) != 0) {
    return false;
  }
  // Match porter ensure_owned_dir: skip root->other chown (rootless Podman).
  if (geteuid() != 0 || uid == 0) {
    if (chown(dir.c_str(), uid, gid) == -1) {
      return false;
    }
  }
  return true;
}

std::string safe_write_exclusive(const std::string &dir,
                                 const std::string &name,
                                 const std::string &content,
                                 uid_t uid,
                                 gid_t gid,
                                 mode_t mode) {
  if (dir.empty() || name.empty() || name.find('/') != std::string::npos || name == "." || name == "..") {
    return "";
  }
  if (!ensure_private_dir(dir, uid, gid)) {
    return "";
  }
  const std::string path = dir + "/" + name;
  const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode);
  if (fd < 0) {
    return "";
  }
  const char *p = content.data();
  size_t left = content.size();
  while (left > 0) {
    const ssize_t n = write(fd, p, left);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      close(fd);
      unlink(path.c_str());
      return "";
    }
    p += static_cast<size_t>(n);
    left -= static_cast<size_t>(n);
  }
  if (fchmod(fd, mode) != 0) {
    close(fd);
    unlink(path.c_str());
    return "";
  }
  if (fchown(fd, uid, gid) != 0) {
    // Rootless: root->other chown can fail; keep file if mode is already restrictive.
    if (!(geteuid() == 0 && uid != 0)) {
      close(fd);
      unlink(path.c_str());
      return "";
    }
  }
  if (close(fd) != 0) {
    unlink(path.c_str());
    return "";
  }
  return path;
}

}  // namespace swm
