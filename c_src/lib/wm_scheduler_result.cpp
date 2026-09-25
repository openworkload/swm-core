#include <iostream>

#include "wm_scheduler_result.h"

#include <ei.h>

#include "wm_metric.h"
#include "wm_timetable.h"

using namespace swm;


SwmSchedulerResult::SwmSchedulerResult() {
}

SwmSchedulerResult::SwmSchedulerResult(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmSchedulerResult: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmSchedulerResult header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmSchedulerResult term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_timetable(buf, index, this->timetable)) {
    std::cerr << "Could not init scheduler_result::timetable at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_metric(buf, index, this->metrics)) {
    std::cerr << "Could not init scheduler_result::metrics at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->request_id)) {
    std::cerr << "Could not init scheduler_result::request_id at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->status)) {
    std::cerr << "Could not init scheduler_result::status at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_double(buf, index, this->astro_time)) {
    std::cerr << "Could not init scheduler_result::astro_time at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_double(buf, index, this->idle_time)) {
    std::cerr << "Could not init scheduler_result::idle_time at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_double(buf, index, this->work_time)) {
    std::cerr << "Could not init scheduler_result::work_time at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_scheduler_result(const char *buf, int &index, std::vector<SwmSchedulerResult> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a scheduler_result list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for scheduler_result at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (int i=0; i<list_size; ++i) {
    int entry_size = 0;
    int sub_term_type = 0;
    const int parsed = ei_get_type(buf, &index, &sub_term_type, &entry_size);
    if (parsed < 0) {
      std::cerr << "Could not get term type at position " << index << std::endl;
      return -1;
    }
    switch (sub_term_type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << ") is not a tuple" << std::endl;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_scheduler_result(const char* buf, int &index, SwmSchedulerResult &obj) {
  obj = SwmSchedulerResult(buf, index);
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

