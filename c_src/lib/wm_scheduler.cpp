

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_scheduler.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_executable.h"

using namespace swm;


SwmScheduler::SwmScheduler() {
}

SwmScheduler::SwmScheduler(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmScheduler: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize scheduler paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize scheduler paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, state)) {
    std::cerr << "Could not initialize scheduler paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, start_time)) {
    std::cerr << "Could not initialize scheduler paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, stop_time)) {
    std::cerr << "Could not initialize scheduler paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 7, run_interval)) {
    std::cerr << "Could not initialize scheduler paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_executable(erl_element(8, term), path)) {
    std::cerr << "Could not initialize scheduler paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 9, family)) {
    std::cerr << "Could not initialize scheduler paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 10, version)) {
    std::cerr << "Could not initialize scheduler paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 11, cu)) {
    std::cerr << "Could not initialize scheduler paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 12, comment)) {
    std::cerr << "Could not initialize scheduler paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 13, revision)) {
    std::cerr << "Could not initialize scheduler paremeter at position 13" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmScheduler::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmScheduler::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmScheduler::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmScheduler::set_start_time(const std::string &new_val) {
  start_time = new_val;
}

void SwmScheduler::set_stop_time(const std::string &new_val) {
  stop_time = new_val;
}

void SwmScheduler::set_run_interval(const uint64_t &new_val) {
  run_interval = new_val;
}

void SwmScheduler::set_path(const SwmExecutable &new_val) {
  path = new_val;
}

void SwmScheduler::set_family(const std::string &new_val) {
  family = new_val;
}

void SwmScheduler::set_version(const std::string &new_val) {
  version = new_val;
}

void SwmScheduler::set_cu(const uint64_t &new_val) {
  cu = new_val;
}

void SwmScheduler::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmScheduler::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmScheduler::get_id() const {
  return id;
}

std::string SwmScheduler::get_name() const {
  return name;
}

std::string SwmScheduler::get_state() const {
  return state;
}

std::string SwmScheduler::get_start_time() const {
  return start_time;
}

std::string SwmScheduler::get_stop_time() const {
  return stop_time;
}

uint64_t SwmScheduler::get_run_interval() const {
  return run_interval;
}

SwmExecutable SwmScheduler::get_path() const {
  return path;
}

std::string SwmScheduler::get_family() const {
  return family;
}

std::string SwmScheduler::get_version() const {
  return version;
}

uint64_t SwmScheduler::get_cu() const {
  return cu;
}

std::string SwmScheduler::get_comment() const {
  return comment;
}

uint64_t SwmScheduler::get_revision() const {
  return revision;
}


int swm::eterm_to_scheduler(ETERM* term, int pos, std::vector<SwmScheduler> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a scheduler list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmScheduler(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_scheduler(ETERM* eterm, SwmScheduler &obj) {
  obj = SwmScheduler(eterm);
  return 0;
}


void SwmScheduler::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << start_time << separator;
    std::cerr << prefix << stop_time << separator;
    std::cerr << prefix << run_interval << separator;
  path.print(prefix, separator);
    std::cerr << prefix << family << separator;
    std::cerr << prefix << version << separator;
    std::cerr << prefix << cu << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


