#include "wm_session.h"

#include "wm_entity_utils.h"

#include <ei.h>

#include <iostream>


using namespace swm;


SwmSession::SwmSession() {
}

SwmSession::SwmSession(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmSession: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize session paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_eterm(term, 3, options)) {
    std::cerr << "Could not initialize session paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, last_status)) {
    std::cerr << "Could not initialize session paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, revision)) {
    std::cerr << "Could not initialize session paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmSession::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmSession::set_options(const ETERM* &new_val) {
  options = const_cast<ETERM*>(new_val);
}

void SwmSession::set_last_status(const std::string &new_val) {
  last_status = new_val;
}

void SwmSession::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmSession::get_id() const {
  return id;
}

ETERM* SwmSession::get_options() const {
  return options;
}

std::string SwmSession::get_last_status() const {
  return last_status;
}

uint64_t SwmSession::get_revision() const {
  return revision;
}


int swm::eterm_to_session(ETERM* term, int pos, std::vector<SwmSession> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a session list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmSession(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_session(ETERM* eterm, SwmSession &obj) {
  obj = SwmSession(eterm);
  return 0;
}


void SwmSession::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << options << separator;
    std::cerr << prefix << last_status << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


