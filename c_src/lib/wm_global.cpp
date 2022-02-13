#include "wm_entity_utils.h"

#include <iostream>

#include "wm_global.h"

#include <ei.h>


using namespace swm;


SwmGlobal::SwmGlobal() {
}

SwmGlobal::SwmGlobal(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmGlobal: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

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


int swm::ei_buffer_to_global(const char* buf, const int pos, std::vector<SwmGlobal> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a global list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for global at position " << pos << std::endl;
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
    array.push_back(SwmGlobal(term));
  }
  return 0;
}


int swm::eterm_to_global(char* buf, SwmGlobal &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << global << std::endl;
    return -1;
  }
  obj = SwmGlobal(eterm);
  return 0;
}


void SwmGlobal::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << value << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


