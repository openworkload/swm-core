

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_metric.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmMetric::SwmMetric() {
}

SwmMetric::SwmMetric(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmMetric: empty" << std::endl;
    return;
  }
  if(eterm_to_atom(term, 2, name)) {
    std::cerr << "Could not initialize metric paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 3, value_integer)) {
    std::cerr << "Could not initialize metric paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_double(term, 4, value_float64)) {
    std::cerr << "Could not initialize metric paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmMetric::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmMetric::set_value_integer(const uint64_t &new_val) {
  value_integer = new_val;
}

void SwmMetric::set_value_float64(const double &new_val) {
  value_float64 = new_val;
}

std::string SwmMetric::get_name() const {
  return name;
}

uint64_t SwmMetric::get_value_integer() const {
  return value_integer;
}

double SwmMetric::get_value_float64() const {
  return value_float64;
}


int swm::eterm_to_metric(ETERM* term, int pos, std::vector<SwmMetric> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a metric list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmMetric(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_metric(ETERM* eterm, SwmMetric &obj) {
  obj = SwmMetric(eterm);
  return 0;
}


void SwmMetric::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << value_integer << separator;
    std::cerr << prefix << value_float64 << separator;
  std::cerr << std::endl;
}


