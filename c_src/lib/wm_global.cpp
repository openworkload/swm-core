#include "wm_entity_utils.h"

#include <iostream>

#include "wm_global.h"

#include <ei.h>


using namespace swm;


SwmGlobal::SwmGlobal() {
}

SwmGlobal::SwmGlobal(const char* buf, int* index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmGlobal: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmGlobal header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->name)) {
    std::cerr << "Could not initialize global property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->value)) {
    std::cerr << "Could not initialize global property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize global property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize global property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

}


void SwmGlobal::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmGlobal::set_value(const std::string &new_val) {
  value = new_val;
}

void SwmGlobal::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmGlobal::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmGlobal::get_name() const {
  return name;
}

std::string SwmGlobal::get_value() const {
  return value;
}

std::string SwmGlobal::get_comment() const {
  return comment;
}

uint64_t SwmGlobal::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_global(const char *buf, const int *index, std::vector<SwmGlobal> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a global list at position " << index << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for " + entity_name + " at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    int entry_size;
    int type;
    int res = ei_get_type(buf, &index, &type, &entry_size);
    switch (type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
      default:
        std::cerr << "List element (at position " << i << " is not a tuple: " << <class 'type'> << std::endl;
    }
  }

  return 0;
}

void SwmGlobal::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << value << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

