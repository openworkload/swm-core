
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_executable.h"

namespace swm {

class SwmScheduler:SwmEntity {

 public:
  SwmScheduler();
  SwmScheduler(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const uint64_t&);
  void set_name(const std::string&);
  void set_state(const std::string&);
  void set_start_time(const std::string&);
  void set_stop_time(const std::string&);
  void set_run_interval(const uint64_t&);
  void set_path(const SwmExecutable&);
  void set_family(const std::string&);
  void set_version(const std::string&);
  void set_cu(const uint64_t&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  uint64_t get_id() const;
  std::string get_name() const;
  std::string get_state() const;
  std::string get_start_time() const;
  std::string get_stop_time() const;
  uint64_t get_run_interval() const;
  SwmExecutable get_path() const;
  std::string get_family() const;
  std::string get_version() const;
  uint64_t get_cu() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  uint64_t id;
  std::string name;
  std::string state;
  std::string start_time;
  std::string stop_time;
  uint64_t run_interval;
  SwmExecutable path;
  std::string family;
  std::string version;
  uint64_t cu;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_scheduler(const char*, int&, std::vector<SwmScheduler>&);
int ei_buffer_to_scheduler(const char*, int&, SwmScheduler&);

} // namespace swm
