
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_executable.h"

namespace swm {

class SwmHook:SwmEntity {

 public:
  SwmHook();
  SwmHook(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_event(const std::string&);
  void set_state(const std::string&);
  void set_executable(const SwmExecutable&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_event() const;
  std::string get_state() const;
  SwmExecutable get_executable() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string event;
  std::string state;
  SwmExecutable executable;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_hook(const char*, int&, std::vector<SwmHook>&);
int ei_buffer_to_hook(const char*, int&, SwmHook&);

} // namespace swm
