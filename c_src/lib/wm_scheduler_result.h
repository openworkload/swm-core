
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_timetable.h"
#include "wm_metric.h"

namespace swm {

class SwmSchedulerResult:SwmEntity {

 public:
  SwmSchedulerResult();
  SwmSchedulerResult(const char*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_timetable(const std::vector<SwmTimetable>&);
  void set_metrics(const std::vector<SwmMetric>&);
  void set_request_id(const std::string&);
  void set_status(const uint64_t&);
  void set_astro_time(const double&);
  void set_idle_time(const double&);
  void set_work_time(const double&);

  std::vector<SwmTimetable> get_timetable() const;
  std::vector<SwmMetric> get_metrics() const;
  std::string get_request_id() const;
  uint64_t get_status() const;
  double get_astro_time() const;
  double get_idle_time() const;
  double get_work_time() const;

 private:
  std::vector<SwmTimetable> timetable;
  std::vector<SwmMetric> metrics;
  std::string request_id;
  uint64_t status;
  double astro_time;
  double idle_time;
  double work_time;

};

int ei_buffer_to_scheduler_result(const char*, int, std::vector<SwmSchedulerResult>&);
int ei_buffer_to_scheduler_result(const char*, SwmSchedulerResult&);

} // namespace swm
