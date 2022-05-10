#include <iostream>

#include "wm_executable.h"

#include <ei.h>


using namespace swm;


SwmExecutable::SwmExecutable() {
}

SwmExecutable::SwmExecutable(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmExecutable: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmExecutable header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmExecutable term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init executable::name at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->path)) {
    std::cerr << "Could not init executable::path at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->user)) {
    std::cerr << "Could not init executable::user at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init executable::comment at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init executable::revision at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmExecutable::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmExecutable::set_path(const std::string &new_val) {
  path = new_val;
}

void SwmExecutable::set_user(const std::string &new_val) {
  user = new_val;
}

void SwmExecutable::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmExecutable::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmExecutable::get_name() const {
  return name;
}

std::string SwmExecutable::get_path() const {
  return path;
}

std::string SwmExecutable::get_user() const {
  return user;
}

std::string SwmExecutable::get_comment() const {
  return comment;
}

uint64_t SwmExecutable::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_executable(const char *buf, int &index, std::vector<SwmExecutable> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a executable list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for executable at position " << index << std::endl;
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

int swm::ei_buffer_to_executable(const char* buf, int &index, SwmExecutable &obj) {
  obj = SwmExecutable(buf, index);
  return 0;
}

void SwmExecutable::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << path << separator;
    std::cerr << prefix << user << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

