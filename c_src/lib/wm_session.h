
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmSession:SwmEntity {

 public:
  SwmSession();
  SwmSession(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_options(const ETERM*&);
  void set_last_status(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  ETERM* get_options() const;
  std::string get_last_status() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  ETERM* options;
  std::string last_status;
  uint64_t revision;

};

int eterm_to_session(ETERM*, int, std::vector<SwmSession>&);
int eterm_to_session(ETERM*, SwmSession&);

} // namespace swm
