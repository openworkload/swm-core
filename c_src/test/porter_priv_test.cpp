#include "wm_porter_priv.h"

#include <grp.h>
#include <gtest/gtest.h>
#include <pwd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>

using swm::drop_privileges;

namespace {

std::set<gid_t> expected_groups(const char *username, gid_t gid) {
  int ngroups = 0;
  getgrouplist(username, gid, nullptr, &ngroups);
  if (ngroups < 1) {
    return {gid};
  }
  std::vector<gid_t> groups(static_cast<size_t>(ngroups));
  if (getgrouplist(username, gid, groups.data(), &ngroups) < 0) {
    return {gid};
  }
  groups.resize(static_cast<size_t>(ngroups));
  return std::set<gid_t>(groups.begin(), groups.end());
}

std::set<gid_t> current_groups() {
  int n = getgroups(0, nullptr);
  if (n < 0) {
    return {};
  }
  std::vector<gid_t> groups(static_cast<size_t>(n));
  if (getgroups(n, groups.data()) < 0) {
    return {};
  }
  return std::set<gid_t>(groups.begin(), groups.end());
}

passwd *non_root_user() {
  if (passwd *pw = getpwnam("nobody")) {
    return pw;
  }
  if (passwd *pw = getpwnam("nfsnobody")) {
    return pw;
  }
  return getpwuid(65534);
}

}  // namespace

TEST(PorterPriv, RejectsEmptyUsername) {
  errno = 0;
  EXPECT_EQ(drop_privileges("", geteuid(), getegid()), -1);
  EXPECT_EQ(errno, EINVAL);
  errno = 0;
  EXPECT_EQ(drop_privileges(nullptr, geteuid(), getegid()), -1);
  EXPECT_EQ(errno, EINVAL);
}

TEST(PorterPriv, DropToSelfWhenNonRoot) {
  if (geteuid() == 0) {
    GTEST_SKIP() << "runs only when not root";
  }
  passwd *pw = getpwuid(geteuid());
  ASSERT_NE(pw, nullptr);
  ASSERT_EQ(drop_privileges(pw->pw_name, pw->pw_uid, pw->pw_gid), 0);
  EXPECT_EQ(getuid(), pw->pw_uid);
  EXPECT_EQ(getgid(), pw->pw_gid);
}

TEST(PorterPriv, RootDropMatchesUserGroups) {
  if (geteuid() != 0) {
    GTEST_SKIP() << "requires root to exercise initgroups";
  }
  passwd *pw = non_root_user();
  ASSERT_NE(pw, nullptr);
  ASSERT_NE(pw->pw_uid, static_cast<uid_t>(0));

  const std::set<gid_t> want = expected_groups(pw->pw_name, pw->pw_gid);
  ASSERT_FALSE(want.empty());

  const pid_t pid = fork();
  ASSERT_GE(pid, 0);
  if (pid == 0) {
    if (drop_privileges(pw->pw_name, pw->pw_uid, pw->pw_gid) != 0) {
      _exit(2);
    }
    if (getuid() != pw->pw_uid || geteuid() != pw->pw_uid) {
      _exit(3);
    }
    if (getgid() != pw->pw_gid || getegid() != pw->pw_gid) {
      _exit(4);
    }
    const std::set<gid_t> got = current_groups();
    if (got != want) {
      _exit(5);
    }
    // Root supplementary group must not linger unless the user is actually in it.
    if (got.count(0) && !want.count(0)) {
      _exit(6);
    }
    _exit(0);
  }

  int status = 0;
  ASSERT_EQ(waitpid(pid, &status, 0), pid);
  ASSERT_TRUE(WIFEXITED(status));
  EXPECT_EQ(WEXITSTATUS(status), 0);
}
