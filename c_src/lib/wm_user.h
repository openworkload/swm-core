
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmUser:SwmEntity {

 public:
  SwmUser();
  SwmUser(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_acl(const std::string&);
  void set_groups(const std::vector<uint64_t>&);
  void set_projects(const std::vector<uint64_t>&);
  void set_priority(const int64_t&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_acl() const;
  std::vector<uint64_t> get_groups() const;
  std::vector<uint64_t> get_projects() const;
  int64_t get_priority() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string acl;
  std::vector<uint64_t> groups;
  std::vector<uint64_t> projects;
  int64_t priority;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_user(const char*, int&, std::vector<SwmUser>&);
int ei_buffer_to_user(const char*, int&, SwmUser&);

} // namespace swm
