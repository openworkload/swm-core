#include "wm_porter_priv.h"

#include <grp.h>
#include <unistd.h>

#include <cerrno>

namespace swm {

int drop_privileges(const char *username, uid_t uid, gid_t gid) {
  if (username == nullptr || username[0] == '\0') {
    errno = EINVAL;
    return -1;
  }

  // Must clear root's supplementary groups while still privileged.
  if (geteuid() == 0) {
    if (initgroups(username, gid) != 0) {
      return -1;
    }
  }

  if (setregid(gid, gid) != 0) {
    return -1;
  }
  if (setreuid(uid, uid) != 0) {
    return -1;
  }
  return 0;
}

}  // namespace swm
