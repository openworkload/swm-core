
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmTimetable:SwmEntity {

 public:
  SwmTimetable();
  SwmTimetable(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_start_time(const uint64_t&);
  void set_job_id(const std::string&);
  void set_job_nodes(const std::vector<std::string>&);

  uint64_t get_start_time() const;
  std::string get_job_id() const;
  std::vector<std::string> get_job_nodes() const;

 private:
  uint64_t start_time;
  std::string job_id;
  std::vector<std::string> job_nodes;

};

int eterm_to_timetable(ETERM*, int, std::vector<SwmTimetable>&);
int eterm_to_timetable(ETERM*, SwmTimetable&);

} // namespace swm
