

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_cluster.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmCluster::SwmCluster() {
}

SwmCluster::SwmCluster(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmCluster: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize cluster paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize cluster paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, state)) {
    std::cerr << "Could not initialize cluster paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, manager)) {
    std::cerr << "Could not initialize cluster paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, partitions)) {
    std::cerr << "Could not initialize cluster paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, hooks)) {
    std::cerr << "Could not initialize cluster paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 8, scheduler)) {
    std::cerr << "Could not initialize cluster paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 9, resources)) {
    std::cerr << "Could not initialize cluster paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_atom_eterm(term, 10, properties)) {
    std::cerr << "Could not initialize cluster paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 11, comment)) {
    std::cerr << "Could not initialize cluster paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 12, revision)) {
    std::cerr << "Could not initialize cluster paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmCluster::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmCluster::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmCluster::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmCluster::set_manager(const std::string &new_val) {
  manager = new_val;
}

void SwmCluster::set_partitions(const std::vector<std::string> &new_val) {
  partitions = new_val;
}

void SwmCluster::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmCluster::set_scheduler(const uint64_t &new_val) {
  scheduler = new_val;
}

void SwmCluster::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

void SwmCluster::set_properties(const std::vector<SwmTupleAtomEterm> &new_val) {
  properties = new_val;
}

void SwmCluster::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmCluster::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmCluster::get_id() const {
  return id;
}

std::string SwmCluster::get_name() const {
  return name;
}

std::string SwmCluster::get_state() const {
  return state;
}

std::string SwmCluster::get_manager() const {
  return manager;
}

std::vector<std::string> SwmCluster::get_partitions() const {
  return partitions;
}

std::vector<std::string> SwmCluster::get_hooks() const {
  return hooks;
}

uint64_t SwmCluster::get_scheduler() const {
  return scheduler;
}

std::vector<SwmResource> SwmCluster::get_resources() const {
  return resources;
}

std::vector<SwmTupleAtomEterm> SwmCluster::get_properties() const {
  return properties;
}

std::string SwmCluster::get_comment() const {
  return comment;
}

uint64_t SwmCluster::get_revision() const {
  return revision;
}


int swm::eterm_to_cluster(ETERM* term, int pos, std::vector<SwmCluster> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a cluster list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmCluster(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_cluster(ETERM* eterm, SwmCluster &obj) {
  obj = SwmCluster(eterm);
  return 0;
}


void SwmCluster::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << manager << separator;
  if(partitions.empty()) {
    std::cerr << prefix << "partitions: []" << separator;
  } else {
    std::cerr << prefix << "partitions" << ": [";
    for(const auto &q: partitions) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for(const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << scheduler << separator;
  if(resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for(const auto &q: resources) {
      q.print(prefix, separator);
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
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


