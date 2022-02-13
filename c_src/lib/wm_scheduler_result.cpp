#include "wm_entity_utils.h"

#include <iostream>

#include "wm_scheduler_result.h"

#include <ei.h>

#include "wm_timetable.h"
#include "wm_metric.h"

using namespace swm;


SwmSchedulerResult::SwmSchedulerResult() {
}

SwmSchedulerResult::SwmSchedulerResult(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmSchedulerResult: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmSchedulerResult header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_timetable(buf, index, this->timetable)) {
    std::cerr << "Could not initialize scheduler_result property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_metric(buf, index, this->metrics)) {
    std::cerr << "Could not initialize scheduler_result property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->request_id)) {
    std::cerr << "Could not initialize scheduler_result property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->status)) {
    std::cerr << "Could not initialize scheduler_result property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_double(buf, index, this->astro_time)) {
    std::cerr << "Could not initialize scheduler_result property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_double(buf, index, this->idle_time)) {
    std::cerr << "Could not initialize scheduler_result property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_double(buf, index, this->work_time)) {
    std::cerr << "Could not initialize scheduler_result property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
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


int swm::ei_buffer_to_scheduler_result(const char* buf, const int pos, std::vector<SwmSchedulerResult> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a scheduler_result list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for scheduler_result at position " << pos << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    ei_term term;
    if (ei_decode_ei_term(buf, pos, &term) < 0) {
      std::cerr << "Could not decode list element at position " << pos << std::endl;
      return -1;
    }
    array.push_back(SwmSchedulerResult(term));
  }
  return 0;
}


int swm::eterm_to_scheduler_result(char* buf, SwmSchedulerResult &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << scheduler_result << std::endl;
    return -1;
  }
  obj = SwmSchedulerResult(eterm);
  return 0;
}


void SwmSchedulerResult::print(const std::string &prefix, const char separator) const {
  if (timetable.empty()) {
    std::cerr << prefix << "timetable: []" << separator;
  } else {
    std::cerr << prefix << "timetable" << ": [";
    for (const auto &q: timetable) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  if (metrics.empty()) {
    std::cerr << prefix << "metrics: []" << separator;
  } else {
    std::cerr << prefix << "metrics" << ": [";
    for (const auto &q: metrics) {
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


