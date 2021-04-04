

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_partition.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmPartition::SwmPartition() {
}

SwmPartition::SwmPartition(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmPartition: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize partition paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize partition paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, state)) {
    std::cerr << "Could not initialize partition paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, manager)) {
    std::cerr << "Could not initialize partition paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, nodes)) {
    std::cerr << "Could not initialize partition paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, partitions)) {
    std::cerr << "Could not initialize partition paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, hooks)) {
    std::cerr << "Could not initialize partition paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 9, scheduler)) {
    std::cerr << "Could not initialize partition paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 10, jobs_per_node)) {
    std::cerr << "Could not initialize partition paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 11, resources)) {
    std::cerr << "Could not initialize partition paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_atom_eterm(term, 12, properties)) {
    std::cerr << "Could not initialize partition paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 13, subdivision)) {
    std::cerr << "Could not initialize partition paremeter at position 13" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 14, subdivision_id)) {
    std::cerr << "Could not initialize partition paremeter at position 14" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 15, created)) {
    std::cerr << "Could not initialize partition paremeter at position 15" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 16, updated)) {
    std::cerr << "Could not initialize partition paremeter at position 16" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 17, external_id)) {
    std::cerr << "Could not initialize partition paremeter at position 17" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_eterm(term, 18, addresses)) {
    std::cerr << "Could not initialize partition paremeter at position 18" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 19, comment)) {
    std::cerr << "Could not initialize partition paremeter at position 19" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 20, revision)) {
    std::cerr << "Could not initialize partition paremeter at position 20" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmPartition::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmPartition::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmPartition::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmPartition::set_manager(const std::string &new_val) {
  manager = new_val;
}

void SwmPartition::set_nodes(const std::vector<std::string> &new_val) {
  nodes = new_val;
}

void SwmPartition::set_partitions(const std::vector<std::string> &new_val) {
  partitions = new_val;
}

void SwmPartition::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmPartition::set_scheduler(const uint64_t &new_val) {
  scheduler = new_val;
}

void SwmPartition::set_jobs_per_node(const uint64_t &new_val) {
  jobs_per_node = new_val;
}

void SwmPartition::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

void SwmPartition::set_properties(const std::vector<SwmTupleAtomEterm> &new_val) {
  properties = new_val;
}

void SwmPartition::set_subdivision(const std::string &new_val) {
  subdivision = new_val;
}

void SwmPartition::set_subdivision_id(const std::string &new_val) {
  subdivision_id = new_val;
}

void SwmPartition::set_created(const std::string &new_val) {
  created = new_val;
}

void SwmPartition::set_updated(const std::string &new_val) {
  updated = new_val;
}

void SwmPartition::set_external_id(const std::string &new_val) {
  external_id = new_val;
}

void SwmPartition::set_addresses(const ETERM* &new_val) {
  addresses = const_cast<ETERM*>(new_val);
}

void SwmPartition::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmPartition::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmPartition::get_id() const {
  return id;
}

std::string SwmPartition::get_name() const {
  return name;
}

std::string SwmPartition::get_state() const {
  return state;
}

std::string SwmPartition::get_manager() const {
  return manager;
}

std::vector<std::string> SwmPartition::get_nodes() const {
  return nodes;
}

std::vector<std::string> SwmPartition::get_partitions() const {
  return partitions;
}

std::vector<std::string> SwmPartition::get_hooks() const {
  return hooks;
}

uint64_t SwmPartition::get_scheduler() const {
  return scheduler;
}

uint64_t SwmPartition::get_jobs_per_node() const {
  return jobs_per_node;
}

std::vector<SwmResource> SwmPartition::get_resources() const {
  return resources;
}

std::vector<SwmTupleAtomEterm> SwmPartition::get_properties() const {
  return properties;
}

std::string SwmPartition::get_subdivision() const {
  return subdivision;
}

std::string SwmPartition::get_subdivision_id() const {
  return subdivision_id;
}

std::string SwmPartition::get_created() const {
  return created;
}

std::string SwmPartition::get_updated() const {
  return updated;
}

std::string SwmPartition::get_external_id() const {
  return external_id;
}

ETERM* SwmPartition::get_addresses() const {
  return addresses;
}

std::string SwmPartition::get_comment() const {
  return comment;
}

uint64_t SwmPartition::get_revision() const {
  return revision;
}


int swm::eterm_to_partition(ETERM* term, int pos, std::vector<SwmPartition> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a partition list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmPartition(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_partition(ETERM* eterm, SwmPartition &obj) {
  obj = SwmPartition(eterm);
  return 0;
}


void SwmPartition::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << manager << separator;
  if(nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for(const auto &q: nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
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
    std::cerr << prefix << jobs_per_node << separator;
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
    std::cerr << prefix << subdivision << separator;
    std::cerr << prefix << subdivision_id << separator;
    std::cerr << prefix << created << separator;
    std::cerr << prefix << updated << separator;
    std::cerr << prefix << external_id << separator;
    std::cerr << prefix << addresses << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


