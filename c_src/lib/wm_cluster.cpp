#include "wm_entity_utils.h"

#include <iostream>

#include "wm_cluster.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmCluster::SwmCluster() {
}

SwmCluster::SwmCluster(const char* buf, int* index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmCluster: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmCluster header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not initialize cluster property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize cluster property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not initialize cluster property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->manager)) {
    std::cerr << "Could not initialize cluster property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->partitions)) {
    std::cerr << "Could not initialize cluster property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not initialize cluster property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->scheduler)) {
    std::cerr << "Could not initialize cluster property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not initialize cluster property at position=9" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_tuple_atom_eterm(buf, index, this->properties)) {
    std::cerr << "Could not initialize cluster property at position=10" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize cluster property at position=11" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize cluster property at position=12" << std::endl;
    ei_print_term(stderr, buf, index);
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

int swm::ei_buffer_to_cluster(const char *buf, const int *index, std::vector<SwmCluster> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a cluster list at position " << index << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for " + entity_name + " at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    int entry_size;
    int type;
    int res = ei_get_type(buf, &index, &type, &entry_size);
    switch (type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
      default:
        std::cerr << "List element (at position " << i << " is not a tuple: " << <class 'type'> << std::endl;
    }
  }

  return 0;
}

void SwmCluster::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << manager << separator;
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
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

