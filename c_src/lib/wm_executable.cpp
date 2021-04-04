

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_executable.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmExecutable::SwmExecutable() {
}

SwmExecutable::SwmExecutable(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmExecutable: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, name)) {
    std::cerr << "Could not initialize executable paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, path)) {
    std::cerr << "Could not initialize executable paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, user)) {
    std::cerr << "Could not initialize executable paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, comment)) {
    std::cerr << "Could not initialize executable paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 6, revision)) {
    std::cerr << "Could not initialize executable paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
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


int swm::eterm_to_executable(ETERM* term, int pos, std::vector<SwmExecutable> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a executable list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmExecutable(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_executable(ETERM* eterm, SwmExecutable &obj) {
  obj = SwmExecutable(eterm);
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


