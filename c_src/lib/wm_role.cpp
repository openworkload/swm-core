

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_role.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmRole::SwmRole() {
}

SwmRole::SwmRole(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmRole: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize role paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize role paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 4, services)) {
    std::cerr << "Could not initialize role paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, comment)) {
    std::cerr << "Could not initialize role paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 6, revision)) {
    std::cerr << "Could not initialize role paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmRole::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmRole::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmRole::set_services(const std::vector<uint64_t> &new_val) {
  services = new_val;
}

void SwmRole::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmRole::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmRole::get_id() const {
  return id;
}

std::string SwmRole::get_name() const {
  return name;
}

std::vector<uint64_t> SwmRole::get_services() const {
  return services;
}

std::string SwmRole::get_comment() const {
  return comment;
}

uint64_t SwmRole::get_revision() const {
  return revision;
}


int swm::eterm_to_role(ETERM* term, int pos, std::vector<SwmRole> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a role list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmRole(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_role(ETERM* eterm, SwmRole &obj) {
  obj = SwmRole(eterm);
  return 0;
}


void SwmRole::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
  if(services.empty()) {
    std::cerr << prefix << "services: []" << separator;
  } else {
    std::cerr << prefix << "services" << ": [";
    for(const auto &q: services) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


