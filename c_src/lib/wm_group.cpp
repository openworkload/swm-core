

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_group.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmGroup::SwmGroup() {
}

SwmGroup::SwmGroup(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmGroup: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize group paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize group paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, acl)) {
    std::cerr << "Could not initialize group paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 5, priority)) {
    std::cerr << "Could not initialize group paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, comment)) {
    std::cerr << "Could not initialize group paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 7, revision)) {
    std::cerr << "Could not initialize group paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmGroup::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmGroup::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmGroup::set_acl(const std::string &new_val) {
  acl = new_val;
}

void SwmGroup::set_priority(const int64_t &new_val) {
  priority = new_val;
}

void SwmGroup::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmGroup::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmGroup::get_id() const {
  return id;
}

std::string SwmGroup::get_name() const {
  return name;
}

std::string SwmGroup::get_acl() const {
  return acl;
}

int64_t SwmGroup::get_priority() const {
  return priority;
}

std::string SwmGroup::get_comment() const {
  return comment;
}

uint64_t SwmGroup::get_revision() const {
  return revision;
}


int swm::eterm_to_group(ETERM* term, int pos, std::vector<SwmGroup> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a group list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmGroup(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_group(ETERM* eterm, SwmGroup &obj) {
  obj = SwmGroup(eterm);
  return 0;
}


void SwmGroup::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << acl << separator;
    std::cerr << prefix << priority << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


