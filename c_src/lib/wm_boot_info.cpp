#include "wm_entity_utils.h"

#include <iostream>

#include "wm_boot_info.h"

#include <ei.h>


using namespace swm;


SwmBootInfo::SwmBootInfo() {
}

SwmBootInfo::SwmBootInfo(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmBootInfo: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmBootInfo header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->node_host)) {
    std::cerr << "Could not initialize boot_info property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->node_port)) {
    std::cerr << "Could not initialize boot_info property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->parent_host)) {
    std::cerr << "Could not initialize boot_info property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->parent_port)) {
    std::cerr << "Could not initialize boot_info property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
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


int swm::ei_buffer_to_boot_info(const char* buf, const int pos, std::vector<SwmBootInfo> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a boot_info list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for boot_info at position " << pos << std::endl;
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
    array.push_back(SwmBootInfo(term));
  }
  return 0;
}


int swm::eterm_to_boot_info(char* buf, SwmBootInfo &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << boot_info << std::endl;
    return -1;
  }
  obj = SwmBootInfo(eterm);
  return 0;
}


void SwmBootInfo::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << node_host << separator;
    std::cerr << prefix << node_port << separator;
    std::cerr << prefix << parent_host << separator;
    std::cerr << prefix << parent_port << separator;
  std::cerr << std::endl;
}


