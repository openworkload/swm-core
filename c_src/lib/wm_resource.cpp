

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_resource.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmResource::SwmResource() {
}

SwmResource::SwmResource(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmResource: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, name)) {
    std::cerr << "Could not initialize resource paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 3, count)) {
    std::cerr << "Could not initialize resource paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, hooks)) {
    std::cerr << "Could not initialize resource paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_atom_eterm(term, 5, properties)) {
    std::cerr << "Could not initialize resource paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_eterm(term, 6, prices)) {
    std::cerr << "Could not initialize resource paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 7, usage_time)) {
    std::cerr << "Could not initialize resource paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 8, resources)) {
    std::cerr << "Could not initialize resource paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmResource::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmResource::set_count(const uint64_t &new_val) {
  count = new_val;
}

void SwmResource::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmResource::set_properties(const std::vector<SwmTupleAtomEterm> &new_val) {
  properties = new_val;
}

void SwmResource::set_prices(const ETERM* &new_val) {
  prices = const_cast<ETERM*>(new_val);
}

void SwmResource::set_usage_time(const uint64_t &new_val) {
  usage_time = new_val;
}

void SwmResource::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

std::string SwmResource::get_name() const {
  return name;
}

uint64_t SwmResource::get_count() const {
  return count;
}

std::vector<std::string> SwmResource::get_hooks() const {
  return hooks;
}

std::vector<SwmTupleAtomEterm> SwmResource::get_properties() const {
  return properties;
}

ETERM* SwmResource::get_prices() const {
  return prices;
}

uint64_t SwmResource::get_usage_time() const {
  return usage_time;
}

std::vector<SwmResource> SwmResource::get_resources() const {
  return resources;
}


int swm::eterm_to_resource(ETERM* term, int pos, std::vector<SwmResource> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a resource list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmResource(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_resource(ETERM* eterm, SwmResource &obj) {
  obj = SwmResource(eterm);
  return 0;
}


void SwmResource::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << count << separator;
  if(hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for(const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(properties.empty()) {
    std::cerr << prefix << "properties: []" << separator;
  } else {
    std::cerr << prefix << "properties" << ": [";
    for(const auto &q: properties) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << prices << separator;
    std::cerr << prefix << usage_time << separator;
  if(resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for(const auto &q: resources) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  std::cerr << std::endl;
}


