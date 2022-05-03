#include "wm_entity_utils.h"

#include <iostream>

#include "wm_boot_info.h"

#include <ei.h>


using namespace swm;


SwmBootInfo::SwmBootInfo() {
}

SwmBootInfo::SwmBootInfo(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmBootInfo: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmBootInfo header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmBootInfo term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->node_host)) {
    std::cerr << "Could not init boot_info::node_host at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->node_port)) {
    std::cerr << "Could not init boot_info::node_port at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->parent_host)) {
    std::cerr << "Could not init boot_info::parent_host at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->parent_port)) {
    std::cerr << "Could not init boot_info::parent_port at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmBootInfo::set_node_host(const std::string &new_val) {
  node_host = new_val;
}

void SwmBootInfo::set_node_port(const uint64_t &new_val) {
  node_port = new_val;
}

void SwmBootInfo::set_parent_host(const std::string &new_val) {
  parent_host = new_val;
}

void SwmBootInfo::set_parent_port(const uint64_t &new_val) {
  parent_port = new_val;
}

std::string SwmBootInfo::get_node_host() const {
  return node_host;
}

uint64_t SwmBootInfo::get_node_port() const {
  return node_port;
}

std::string SwmBootInfo::get_parent_host() const {
  return parent_host;
}

uint64_t SwmBootInfo::get_parent_port() const {
  return parent_port;
}

int swm::ei_buffer_to_boot_info(const char *buf, int &index, std::vector<SwmBootInfo> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a boot_info list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for boot_info at position " << index << std::endl;
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

int swm::ei_buffer_to_boot_info(const char* buf, int &index, SwmBootInfo &obj) {
  obj = SwmBootInfo(buf, index);
  return 0;
}

void SwmBootInfo::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << node_host << separator;
    std::cerr << prefix << node_port << separator;
    std::cerr << prefix << parent_host << separator;
    std::cerr << prefix << parent_port << separator;
  std::cerr << std::endl;
}

