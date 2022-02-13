
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmProject:SwmEntity {

 public:
  SwmProject();
  SwmProject(const char*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const uint64_t&);
  void set_name(const std::string&);
  void set_acl(const std::string&);
  void set_hooks(const std::vector<std::string>&);
  void set_priority(const int64_t&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  uint64_t get_id() const;
  std::string get_name() const;
  std::string get_acl() const;
  std::vector<std::string> get_hooks() const;
  int64_t get_priority() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  uint64_t id;
  std::string name;
  std::string acl;
  std::vector<std::string> hooks;
  int64_t priority;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_project(const char*, int, std::vector<SwmProject>&);
int ei_buffer_to_project(const char*, SwmProject&);

} // namespace swm
