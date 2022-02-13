
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmExecutable:SwmEntity {

 public:
  SwmExecutable();
  SwmExecutable(const char*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_name(const std::string&);
  void set_path(const std::string&);
  void set_user(const std::string&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_name() const;
  std::string get_path() const;
  std::string get_user() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string name;
  std::string path;
  std::string user;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_executable(const char*, int, std::vector<SwmExecutable>&);
int ei_buffer_to_executable(const char*, SwmExecutable&);

} // namespace swm
