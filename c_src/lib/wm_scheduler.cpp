#include "wm_entity_utils.h"

#include <iostream>

#include "wm_scheduler.h"

#include <ei.h>

#include "wm_executable.h"

using namespace swm;


SwmScheduler::SwmScheduler() {
}

SwmScheduler::SwmScheduler(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmScheduler: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmScheduler header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not initialize scheduler property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize scheduler property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not initialize scheduler property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->start_time)) {
    std::cerr << "Could not initialize scheduler property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->stop_time)) {
    std::cerr << "Could not initialize scheduler property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->run_interval)) {
    std::cerr << "Could not initialize scheduler property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_executable(buf, index, this->path)) {
    std::cerr << "Could not initialize scheduler property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->family)) {
    std::cerr << "Could not initialize scheduler property at position=9" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->version)) {
    std::cerr << "Could not initialize scheduler property at position=10" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->cu)) {
    std::cerr << "Could not initialize scheduler property at position=11" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize scheduler property at position=12" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize scheduler property at position=13" << std::endl;
    ei_print_term(stderr, buf, index);
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


int swm::ei_buffer_to_scheduler(const char* buf, const int pos, std::vector<SwmScheduler> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a scheduler list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for scheduler at position " << pos << std::endl;
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
    array.push_back(SwmScheduler(term));
  }
  return 0;
}


int swm::eterm_to_scheduler(char* buf, SwmScheduler &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << scheduler << std::endl;
    return -1;
  }
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


