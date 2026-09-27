#pragma once

#include <string>
#include <vector>

namespace swm {

// Create AF_UNIX listen socket; returns path and listen fd, or empty path on failure.
std::string porter_ctrl_listen(int *listen_fd_out);

// Accept one client (non-blocking friendly); returns client fd or -1.
int porter_ctrl_accept(int listen_fd);

// Parse SPAWN line into pmix flag + argv; returns false on parse error.
bool porter_ctrl_parse_spawn(const std::string &line, bool *pmix_out, std::vector<std::string> *argv_out);

// Send Erlang {porter_req, Ref, Method, ArgsMap} on Porter parent stdout.
// ArgsMap is encoded as a proplist [{atom, value}, ...].
int send_porter_req(const std::string &ref, const char *method, bool pmix, const std::vector<std::string> &argv);

// Encode DONE/ERR/OK line to client fd.
bool porter_ctrl_write_line(int fd, const std::string &line);

}  // namespace swm
