

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_hook.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_executable.h"

using namespace swm;


SwmHook::SwmHook() {
}

SwmHook::SwmHook(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmHook: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize hook paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize hook paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, event)) {
    std::cerr << "Could not initialize hook paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 5, state)) {
    std::cerr << "Could not initialize hook paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_executable(erl_element(6, term), executable)) {
    std::cerr << "Could not initialize hook paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, comment)) {
    std::cerr << "Could not initialize hook paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 8, revision)) {
    std::cerr << "Could not initialize hook paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmHook::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmHook::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmHook::set_event(const std::string &new_val) {
  event = new_val;
}

void SwmHook::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmHook::set_executable(const SwmExecutable &new_val) {
  executable = new_val;
}

void SwmHook::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmHook::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmHook::get_id() const {
  return id;
}

std::string SwmHook::get_name() const {
  return name;
}

std::string SwmHook::get_event() const {
  return event;
}

std::string SwmHook::get_state() const {
  return state;
}

SwmExecutable SwmHook::get_executable() const {
  return executable;
}

std::string SwmHook::get_comment() const {
  return comment;
}

uint64_t SwmHook::get_revision() const {
  return revision;
}


int swm::eterm_to_hook(ETERM* term, int pos, std::vector<SwmHook> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a hook list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmHook(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_hook(ETERM* eterm, SwmHook &obj) {
  obj = SwmHook(eterm);
  return 0;
}


void SwmHook::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << event << separator;
    std::cerr << prefix << state << separator;
  executable.print(prefix, separator);
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


