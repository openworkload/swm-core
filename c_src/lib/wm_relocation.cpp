

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_relocation.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmRelocation::SwmRelocation() {
}

SwmRelocation::SwmRelocation(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmRelocation: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize relocation paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, job_id)) {
    std::cerr << "Could not initialize relocation paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, cancaled)) {
    std::cerr << "Could not initialize relocation paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmRelocation::set_id(const std::uint64_t &new_val) {
  id = new_val;
}

void SwmRelocation::set_job_id(const std::string &new_val) {
  job_id = new_val;
}

void SwmRelocation::set_cancaled(const std::string &new_val) {
  cancaled = new_val;
}

std::uint64_t SwmRelocation::get_id() const {
  return id;
}

std::string SwmRelocation::get_job_id() const {
  return job_id;
}

std::string SwmRelocation::get_cancaled() const {
  return cancaled;
}


int swm::eterm_to_relocation(ETERM* term, int pos, std::vector<SwmRelocation> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a relocation list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmRelocation(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_relocation(ETERM* eterm, SwmRelocation &obj) {
  obj = SwmRelocation(eterm);
  return 0;
}


void SwmRelocation::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << job_id << separator;
    std::cerr << prefix << cancaled << separator;
  std::cerr << std::endl;
}


