#include <iostream>

#include "wm_hook.h"

#include <ei.h>

#include "wm_executable.h"

using namespace swm;


SwmHook::SwmHook() {
}

SwmHook::SwmHook(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmHook: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmHook header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmHook term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init hook::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init hook::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->event)) {
    std::cerr << "Could not init hook::event at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not init hook::state at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_executable(buf, index, this->executable)) {
    std::cerr << "Could not init hook::executable at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init hook::comment at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init hook::revision at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmHook::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmHook::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmHook::set_event(const std::string &new_val) {
  event = new_val;
}

void SwmHook::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmHook::set_executable(const SwmExecutable &new_val) {
  executable = new_val;
}

void SwmHook::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmHook::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmHook::get_id() const {
  return id;
}

std::string SwmHook::get_name() const {
  return name;
}

std::string SwmHook::get_event() const {
  return event;
}

std::string SwmHook::get_state() const {
  return state;
}

SwmExecutable SwmHook::get_executable() const {
  return executable;
}

std::string SwmHook::get_comment() const {
  return comment;
}

uint64_t SwmHook::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_hook(const char *buf, int &index, std::vector<SwmHook> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a hook list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for hook at position " << index << std::endl;
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

int swm::ei_buffer_to_hook(const char* buf, int &index, SwmHook &obj) {
  obj = SwmHook(buf, index);
  return 0;
}

void SwmHook::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << id << separator;
  std::cerr << prefix << name << separator;
  std::cerr << prefix << event << separator;
  std::cerr << prefix << state << separator;
  executable.print(prefix, separator);
  std::cerr << prefix << comment << separator;
  std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

