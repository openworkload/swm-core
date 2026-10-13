#pragma once

#include <sys/types.h>

namespace swm {

/// Drop to job user: initgroups (when euid is 0), then setgid/setuid.
/// Returns 0 on success, -1 on failure (errno set).
int drop_privileges(const char *username, uid_t uid, gid_t gid);

}  // namespace swm
