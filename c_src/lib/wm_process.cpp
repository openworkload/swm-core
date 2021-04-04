

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_process.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmProcess::SwmProcess() {
}

SwmProcess::SwmProcess(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmProcess: empty" << std::endl;
    return;
  }
  if(eterm_to_int64_t(term, 2, pid)) {
    std::cerr << "Could not initialize process paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, state)) {
    std::cerr << "Could not initialize process paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 4, exitcode)) {
    std::cerr << "Could not initialize process paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 5, signal)) {
    std::cerr << "Could not initialize process paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, comment)) {
    std::cerr << "Could not initialize process paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmProcess::set_pid(const int64_t &new_val) {
  pid = new_val;
}

void SwmProcess::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmProcess::set_exitcode(const int64_t &new_val) {
  exitcode = new_val;
}

void SwmProcess::set_signal(const int64_t &new_val) {
  signal = new_val;
}

void SwmProcess::set_comment(const std::string &new_val) {
  comment = new_val;
}

int64_t SwmProcess::get_pid() const {
  return pid;
}

std::string SwmProcess::get_state() const {
  return state;
}

int64_t SwmProcess::get_exitcode() const {
  return exitcode;
}

int64_t SwmProcess::get_signal() const {
  return signal;
}

std::string SwmProcess::get_comment() const {
  return comment;
}


int swm::eterm_to_process(ETERM* term, int pos, std::vector<SwmProcess> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a process list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmProcess(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_process(ETERM* eterm, SwmProcess &obj) {
  obj = SwmProcess(eterm);
  return 0;
}


void SwmProcess::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << pid << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << exitcode << separator;
    std::cerr << prefix << signal << separator;
    std::cerr << prefix << comment << separator;
  std::cerr << std::endl;
}


