

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_remote.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmRemote::SwmRemote() {
}

SwmRemote::SwmRemote(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmRemote: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize remote paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, account_id)) {
    std::cerr << "Could not initialize remote paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, name)) {
    std::cerr << "Could not initialize remote paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 5, kind)) {
    std::cerr << "Could not initialize remote paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, server)) {
    std::cerr << "Could not initialize remote paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 7, port)) {
    std::cerr << "Could not initialize remote paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 8, revision)) {
    std::cerr << "Could not initialize remote paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmRemote::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmRemote::set_account_id(const std::string &new_val) {
  account_id = new_val;
}

void SwmRemote::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmRemote::set_kind(const std::string &new_val) {
  kind = new_val;
}

void SwmRemote::set_server(const std::string &new_val) {
  server = new_val;
}

void SwmRemote::set_port(const uint64_t &new_val) {
  port = new_val;
}

void SwmRemote::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmRemote::get_id() const {
  return id;
}

std::string SwmRemote::get_account_id() const {
  return account_id;
}

std::string SwmRemote::get_name() const {
  return name;
}

std::string SwmRemote::get_kind() const {
  return kind;
}

std::string SwmRemote::get_server() const {
  return server;
}

uint64_t SwmRemote::get_port() const {
  return port;
}

uint64_t SwmRemote::get_revision() const {
  return revision;
}


int swm::eterm_to_remote(ETERM* term, int pos, std::vector<SwmRemote> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a remote list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmRemote(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_remote(ETERM* eterm, SwmRemote &obj) {
  obj = SwmRemote(eterm);
  return 0;
}


void SwmRemote::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << account_id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << kind << separator;
    std::cerr << prefix << server << separator;
    std::cerr << prefix << port << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


