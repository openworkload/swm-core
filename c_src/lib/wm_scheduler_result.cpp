

#include "wm_scheduler_result.h"

#include "wm_entity_utils.h"
#include "wm_metric.h"
#include "wm_timetable.h"

#include <iostream>

#include <erl_interface.h>
#include <ei.h>

using namespace swm;


SwmSchedulerResult::SwmSchedulerResult() {
}

SwmSchedulerResult::SwmSchedulerResult(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmSchedulerResult: empty" << std::endl;
    return;
  }
  if(eterm_to_timetable(term, 2, timetable)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_metric(term, 3, metrics)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, request_id)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, status)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_double(term, 6, astro_time)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_double(term, 7, idle_time)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_double(term, 8, work_time)) {
    std::cerr << "Could not initialize scheduler_result paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmSchedulerResult::set_timetable(const std::vector<SwmTimetable> &new_val) {
  timetable = new_val;
}

void SwmSchedulerResult::set_metrics(const std::vector<SwmMetric> &new_val) {
  metrics = new_val;
}

void SwmSchedulerResult::set_request_id(const std::string &new_val) {
  request_id = new_val;
}

void SwmSchedulerResult::set_status(const uint64_t &new_val) {
  status = new_val;
}

void SwmSchedulerResult::set_astro_time(const double &new_val) {
  astro_time = new_val;
}

void SwmSchedulerResult::set_idle_time(const double &new_val) {
  idle_time = new_val;
}

void SwmSchedulerResult::set_work_time(const double &new_val) {
  work_time = new_val;
}

std::vector<SwmTimetable> SwmSchedulerResult::get_timetable() const {
  return timetable;
}

std::vector<SwmMetric> SwmSchedulerResult::get_metrics() const {
  return metrics;
}

std::string SwmSchedulerResult::get_request_id() const {
  return request_id;
}

uint64_t SwmSchedulerResult::get_status() const {
  return status;
}

double SwmSchedulerResult::get_astro_time() const {
  return astro_time;
}

double SwmSchedulerResult::get_idle_time() const {
  return idle_time;
}

double SwmSchedulerResult::get_work_time() const {
  return work_time;
}


int swm::eterm_to_scheduler_result(ETERM* term, int pos, std::vector<SwmSchedulerResult> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a scheduler_result list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmSchedulerResult(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_scheduler_result(ETERM* eterm, SwmSchedulerResult &obj) {
  obj = SwmSchedulerResult(eterm);
  return 0;
}


void SwmSchedulerResult::print(const std::string &prefix, const char separator) const {
  if(timetable.empty()) {
    std::cerr << prefix << "timetable: []" << separator;
  } else {
    std::cerr << prefix << "timetable" << ": [";
    for(const auto &q: timetable) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  if(metrics.empty()) {
    std::cerr << prefix << "metrics: []" << separator;
  } else {
    std::cerr << prefix << "metrics" << ": [";
    for(const auto &q: metrics) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << request_id << separator;
    std::cerr << prefix << status << separator;
    std::cerr << prefix << astro_time << separator;
    std::cerr << prefix << idle_time << separator;
    std::cerr << prefix << work_time << separator;
  std::cerr << std::endl;
}


