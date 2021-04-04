

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_timetable.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmTimetable::SwmTimetable() {
}

SwmTimetable::SwmTimetable(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmTimetable: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, start_time)) {
    std::cerr << "Could not initialize timetable paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, job_id)) {
    std::cerr << "Could not initialize timetable paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, job_nodes)) {
    std::cerr << "Could not initialize timetable paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
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


int swm::eterm_to_timetable(ETERM* term, int pos, std::vector<SwmTimetable> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a timetable list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmTimetable(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_timetable(ETERM* eterm, SwmTimetable &obj) {
  obj = SwmTimetable(eterm);
  return 0;
}


void SwmTimetable::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << start_time << separator;
    std::cerr << prefix << job_id << separator;
  if(job_nodes.empty()) {
    std::cerr << prefix << "job_nodes: []" << separator;
  } else {
    std::cerr << prefix << "job_nodes" << ": [";
    for(const auto &q: job_nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << std::endl;
}


