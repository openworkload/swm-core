#include "wm_entity_utils.h"

#include <iostream>

#include "wm_timetable.h"

#include <ei.h>


using namespace swm;


SwmTimetable::SwmTimetable() {
}

SwmTimetable::SwmTimetable(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmTimetable: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmTimetable header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->start_time)) {
    std::cerr << "Could not initialize timetable property at position=2" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_id)) {
    std::cerr << "Could not initialize timetable property at position=3" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_nodes)) {
    std::cerr << "Could not initialize timetable property at position=4" << std::endl;
    ei_print_term(stderr, buf, &index);
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

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a timetable list at position " << index << std::endl;
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
    int type = 0;
    switch (ei_get_type(buf, &index, &type, &entry_size)) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << " is not a tuple: <class 'type'>" << std::endl;
    }
  }

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

