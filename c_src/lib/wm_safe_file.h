#ifndef WM_SAFE_FILE_H
#define WM_SAFE_FILE_H

#include <sys/types.h>

#include <string>

namespace swm {

// Directory for job-private runtime files: $SWM_SPOOL/job/<job_id>.
// Empty job_id returns empty string.
std::string job_runtime_dir(const std::string &job_id);

// Ensure directory exists with mode 0700. Returns false on failure.
bool ensure_private_dir(const std::string &dir, uid_t uid, gid_t gid);

// Write content to dir/name with O_CREAT|O_EXCL|O_NOFOLLOW (no symlink clobber).
// On success returns the absolute path; on failure returns empty string.
std::string safe_write_exclusive(const std::string &dir,
                                 const std::string &name,
                                 const std::string &content,
                                 uid_t uid,
                                 gid_t gid,
                                 mode_t mode = 0700);

}  // namespace swm

#endif
