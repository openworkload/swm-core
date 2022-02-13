#include "wm_entity_utils.h"

#include <iostream>

#include "wm_partition.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmPartition::SwmPartition() {
}

SwmPartition::SwmPartition(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmPartition: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmPartition header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not initialize partition property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize partition property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not initialize partition property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->manager)) {
    std::cerr << "Could not initialize partition property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->nodes)) {
    std::cerr << "Could not initialize partition property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->partitions)) {
    std::cerr << "Could not initialize partition property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not initialize partition property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->scheduler)) {
    std::cerr << "Could not initialize partition property at position=9" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->jobs_per_node)) {
    std::cerr << "Could not initialize partition property at position=10" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not initialize partition property at position=11" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_tuple_atom_eterm(buf, index, this->properties)) {
    std::cerr << "Could not initialize partition property at position=12" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->subdivision)) {
    std::cerr << "Could not initialize partition property at position=13" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->subdivision_id)) {
    std::cerr << "Could not initialize partition property at position=14" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->created)) {
    std::cerr << "Could not initialize partition property at position=15" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->updated)) {
    std::cerr << "Could not initialize partition property at position=16" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->external_id)) {
    std::cerr << "Could not initialize partition property at position=17" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_eterm(buf, index, this->addresses)) {
    std::cerr << "Could not initialize partition property at position=18" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize partition property at position=19" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize partition property at position=20" << std::endl;
    ei_print_term(stderr, buf, index);
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
  addresses = new_val;
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


int swm::ei_buffer_to_partition(const char* buf, const int pos, std::vector<SwmPartition> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a partition list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for partition at position " << pos << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    ei_term term;
    if (ei_decode_ei_term(buf, pos, &term) < 0) {
      std::cerr << "Could not decode list element at position " << pos << std::endl;
      return -1;
    }
    array.push_back(SwmPartition(term));
  }
  return 0;
}


int swm::eterm_to_partition(char* buf, SwmPartition &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << partition << std::endl;
    return -1;
  }
  obj = SwmPartition(eterm);
  return 0;
}


void SwmPartition::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << manager << separator;
  if (nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for (const auto &q: nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (partitions.empty()) {
    std::cerr << prefix << "partitions: []" << separator;
  } else {
    std::cerr << prefix << "partitions" << ": [";
    for (const auto &q: partitions) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for (const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << scheduler << separator;
    std::cerr << prefix << jobs_per_node << separator;
  if (resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for (const auto &q: resources) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  if (properties.empty()) {
    std::cerr << prefix << "properties: []" << separator;
  } else {
    std::cerr << prefix << "properties" << ": [";
    for (const auto &q: properties) {
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


