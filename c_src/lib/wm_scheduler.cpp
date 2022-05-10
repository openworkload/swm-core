#include <iostream>

#include "wm_scheduler.h"

#include <ei.h>

#include "wm_executable.h"

using namespace swm;


SwmScheduler::SwmScheduler() {
}

SwmScheduler::SwmScheduler(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmScheduler: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmScheduler header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmScheduler term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not init scheduler::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init scheduler::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not init scheduler::state at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->start_time)) {
    std::cerr << "Could not init scheduler::start_time at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->stop_time)) {
    std::cerr << "Could not init scheduler::stop_time at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->run_interval)) {
    std::cerr << "Could not init scheduler::run_interval at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_executable(buf, index, this->path)) {
    std::cerr << "Could not init scheduler::path at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->family)) {
    std::cerr << "Could not init scheduler::family at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->version)) {
    std::cerr << "Could not init scheduler::version at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->cu)) {
    std::cerr << "Could not init scheduler::cu at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init scheduler::comment at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init scheduler::revision at pos 13: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_scheduler(const char *buf, int &index, std::vector<SwmScheduler> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a scheduler list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for scheduler at position " << index << std::endl;
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

int swm::ei_buffer_to_scheduler(const char* buf, int &index, SwmScheduler &obj) {
  obj = SwmScheduler(buf, index);
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

