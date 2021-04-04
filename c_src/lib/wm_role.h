
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmRole:SwmEntity {

 public:
  SwmRole();
  SwmRole(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const uint64_t&);
  void set_name(const std::string&);
  void set_services(const std::vector<uint64_t>&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  uint64_t get_id() const;
  std::string get_name() const;
  std::vector<uint64_t> get_services() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  uint64_t id;
  std::string name;
  std::vector<uint64_t> services;
  std::string comment;
  uint64_t revision;

};

int eterm_to_role(ETERM*, int, std::vector<SwmRole>&);
int eterm_to_role(ETERM*, SwmRole&);

} // namespace swm
