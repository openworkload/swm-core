#include <iostream>

#include "wm_relocation.h"

#include <ei.h>


using namespace swm;


SwmRelocation::SwmRelocation() {
}

SwmRelocation::SwmRelocation(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmRelocation: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmRelocation header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmRelocation term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not init relocation::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_id)) {
    std::cerr << "Could not init relocation::job_id at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->template_node_id)) {
    std::cerr << "Could not init relocation::template_node_id at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->canceled)) {
    std::cerr << "Could not init relocation::canceled at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmRelocation::set_id(const std::uint64_t &new_val) {
  id = new_val;
}

void SwmRelocation::set_job_id(const std::string &new_val) {
  job_id = new_val;
}

void SwmRelocation::set_template_node_id(const std::string &new_val) {
  template_node_id = new_val;
}

void SwmRelocation::set_canceled(const std::string &new_val) {
  canceled = new_val;
}

std::uint64_t SwmRelocation::get_id() const {
  return id;
}

std::string SwmRelocation::get_job_id() const {
  return job_id;
}

std::string SwmRelocation::get_template_node_id() const {
  return template_node_id;
}

std::string SwmRelocation::get_canceled() const {
  return canceled;
}

int swm::ei_buffer_to_relocation(const char *buf, int &index, std::vector<SwmRelocation> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a relocation list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for relocation at position " << index << std::endl;
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

int swm::ei_buffer_to_relocation(const char* buf, int &index, SwmRelocation &obj) {
  obj = SwmRelocation(buf, index);
  return 0;
}

void SwmRelocation::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << id << separator;
  std::cerr << prefix << job_id << separator;
  std::cerr << prefix << template_node_id << separator;
  std::cerr << prefix << canceled << separator;
  std::cerr << std::endl;
}

