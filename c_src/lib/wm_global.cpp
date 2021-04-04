

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_global.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmGlobal::SwmGlobal() {
}

SwmGlobal::SwmGlobal(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmGlobal: empty" << std::endl;
    return;
  }
  if(eterm_to_atom(term, 2, name)) {
    std::cerr << "Could not initialize global paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, value)) {
    std::cerr << "Could not initialize global paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, comment)) {
    std::cerr << "Could not initialize global paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, revision)) {
    std::cerr << "Could not initialize global paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
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


int swm::eterm_to_global(ETERM* term, int pos, std::vector<SwmGlobal> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a global list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmGlobal(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_global(ETERM* eterm, SwmGlobal &obj) {
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


