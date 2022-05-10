#include <iostream>

#include "wm_timetable.h"

#include <ei.h>


using namespace swm;


SwmTimetable::SwmTimetable() {
}

SwmTimetable::SwmTimetable(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmTimetable: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmTimetable header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmTimetable term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->start_time)) {
    std::cerr << "Could not init timetable::start_time at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_id)) {
    std::cerr << "Could not init timetable::job_id at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_nodes)) {
    std::cerr << "Could not init timetable::job_nodes at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmTimetable::set_start_time(const uint64_t &new_val) {
  start_time = new_val;
}

void SwmTimetable::set_job_id(const std::string &new_val) {
  job_id = new_val;
}

void SwmTimetable::set_job_nodes(const std::vector<std::string> &new_val) {
  job_nodes = new_val;
}

uint64_t SwmTimetable::get_start_time() const {
  return start_time;
}

std::string SwmTimetable::get_job_id() const {
  return job_id;
}

std::vector<std::string> SwmTimetable::get_job_nodes() const {
  return job_nodes;
}

int swm::ei_buffer_to_timetable(const char *buf, int &index, std::vector<SwmTimetable> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a timetable list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for timetable at position " << index << std::endl;
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

int swm::ei_buffer_to_timetable(const char* buf, int &index, SwmTimetable &obj) {
  obj = SwmTimetable(buf, index);
  return 0;
}

void SwmTimetable::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << start_time << separator;
    std::cerr << prefix << job_id << separator;
  if (job_nodes.empty()) {
    std::cerr << prefix << "job_nodes: []" << separator;
  } else {
    std::cerr << prefix << "job_nodes" << ": [";
    for (const auto &q: job_nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << std::endl;
}

