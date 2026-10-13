#include "wm_safe_file.h"

#include <fcntl.h>
#include <gtest/gtest.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>

using swm::ensure_private_dir;
using swm::job_runtime_dir;
using swm::safe_write_exclusive;

namespace {

std::string make_temp_dir() {
  char tmpl[] = "/tmp/swm-safe-file-test-XXXXXX";
  char *created = mkdtemp(tmpl);
  EXPECT_NE(created, nullptr);
  return created ? std::string(created) : "";
}

}  // namespace

TEST(SafeFile, JobRuntimeDirUsesSpool) {
  const char *prev = std::getenv("SWM_SPOOL");
  ASSERT_EQ(setenv("SWM_SPOOL", "/var/spool/swm", 1), 0);
  EXPECT_EQ(job_runtime_dir("abc-123"), "/var/spool/swm/job/abc-123");
  ASSERT_EQ(setenv("SWM_SPOOL", "/var/spool/swm/", 1), 0);
  EXPECT_EQ(job_runtime_dir("abc-123"), "/var/spool/swm/job/abc-123");
  EXPECT_EQ(job_runtime_dir(""), "");
  unsetenv("SWM_SPOOL");
  EXPECT_EQ(job_runtime_dir("abc-123"), "");
  if (prev) {
    setenv("SWM_SPOOL", prev, 1);
  }
}

TEST(SafeFile, ExclusiveCreateUnderDir) {
  const std::string dir = make_temp_dir();
  ASSERT_FALSE(dir.empty());
  const uid_t uid = geteuid();
  const gid_t gid = getegid();
  const std::string path = safe_write_exclusive(dir, "job.sh", "#!/bin/sh\n", uid, gid, 0700);
  ASSERT_FALSE(path.empty());
  EXPECT_EQ(path, dir + "/job.sh");
  struct stat st {};
  ASSERT_EQ(stat(path.c_str(), &st), 0);
  EXPECT_EQ(st.st_mode & 0777, 0700u);
  std::ifstream in(path);
  std::string body((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  EXPECT_EQ(body, "#!/bin/sh\n");
  unlink(path.c_str());
  rmdir(dir.c_str());
}

TEST(SafeFile, RejectsSymlinkAtTarget) {
  const std::string dir = make_temp_dir();
  ASSERT_FALSE(dir.empty());
  const std::string victim = dir + "/victim";
  {
    std::ofstream out(victim);
    out << "keep-me";
  }
  const std::string link = dir + "/job.sh";
  ASSERT_EQ(symlink(victim.c_str(), link.c_str()), 0);
  const uid_t uid = geteuid();
  const gid_t gid = getegid();
  const std::string path = safe_write_exclusive(dir, "job.sh", "evil", uid, gid, 0700);
  EXPECT_TRUE(path.empty());
  std::ifstream in(victim);
  std::string body((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  EXPECT_EQ(body, "keep-me");
  unlink(link.c_str());
  unlink(victim.c_str());
  rmdir(dir.c_str());
}

TEST(SafeFile, PrivateDirMode0700) {
  const std::string parent = make_temp_dir();
  ASSERT_FALSE(parent.empty());
  const std::string dir = parent + "/job/id1";
  ASSERT_TRUE(ensure_private_dir(dir, geteuid(), getegid()));
  struct stat st {};
  ASSERT_EQ(stat(dir.c_str(), &st), 0);
  EXPECT_EQ(st.st_mode & 0777, 0700u);
  // cleanup
  rmdir(dir.c_str());
  rmdir((parent + "/job").c_str());
  rmdir(parent.c_str());
}
