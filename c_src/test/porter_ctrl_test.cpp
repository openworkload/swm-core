#include "wm_porter_ctrl.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdlib>
#include <string>

#include <gtest/gtest.h>

using swm::porter_ctrl_listen;

TEST(PorterCtrl, SocketMode0600UnderSpool) {
  char tmpl[] = "/tmp/swm-porter-ctrl-test-XXXXXX";
  char *spool = mkdtemp(tmpl);
  ASSERT_NE(spool, nullptr);
  const char *prev = std::getenv("SWM_SPOOL");
  ASSERT_EQ(setenv("SWM_SPOOL", spool, 1), 0);

  int listen_fd = -1;
  const std::string path = porter_ctrl_listen(&listen_fd, "job-42", geteuid(), getegid());
  ASSERT_FALSE(path.empty());
  ASSERT_GE(listen_fd, 0);
  EXPECT_EQ(path, std::string(spool) + "/job/job-42/ctrl.sock");

  struct stat st {};
  ASSERT_EQ(stat(path.c_str(), &st), 0);
  EXPECT_TRUE(S_ISSOCK(st.st_mode));
  EXPECT_EQ(st.st_mode & 0777, 0600u);

  struct stat dst {};
  ASSERT_EQ(stat((std::string(spool) + "/job/job-42").c_str(), &dst), 0);
  EXPECT_EQ(dst.st_mode & 0777, 0700u);

  close(listen_fd);
  unlink(path.c_str());
  rmdir((std::string(spool) + "/job/job-42").c_str());
  rmdir((std::string(spool) + "/job").c_str());
  rmdir(spool);
  if (prev) {
    setenv("SWM_SPOOL", prev, 1);
  } else {
    unsetenv("SWM_SPOOL");
  }
}
