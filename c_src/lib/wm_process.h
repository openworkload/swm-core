
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmProcess:SwmEntity {

 public:
  SwmProcess();
  SwmProcess(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_pid(const int64_t&);
  void set_state(const std::string&);
  void set_exitcode(const int64_t&);
  void set_signal(const int64_t&);
  void set_comment(const std::string&);

  int64_t get_pid() const;
  std::string get_state() const;
  int64_t get_exitcode() const;
  int64_t get_signal() const;
  std::string get_comment() const;

 private:
  int64_t pid;
  std::string state;
  int64_t exitcode;
  int64_t signal;
  std::string comment;

};

int eterm_to_process(ETERM*, int, std::vector<SwmProcess>&);
int eterm_to_process(ETERM*, SwmProcess&);

} // namespace swm
