

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_boot_info.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmBootInfo::SwmBootInfo() {
}

SwmBootInfo::SwmBootInfo(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmBootInfo: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, node_host)) {
    std::cerr << "Could not initialize boot_info paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 3, node_port)) {
    std::cerr << "Could not initialize boot_info paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, parent_host)) {
    std::cerr << "Could not initialize boot_info paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, parent_port)) {
    std::cerr << "Could not initialize boot_info paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
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


int swm::eterm_to_boot_info(ETERM* term, int pos, std::vector<SwmBootInfo> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a boot_info list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmBootInfo(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_boot_info(ETERM* eterm, SwmBootInfo &obj) {
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


