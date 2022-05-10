#include <iostream>

#include "wm_partition.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmPartition::SwmPartition() {
}

SwmPartition::SwmPartition(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmPartition: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmPartition header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmPartition term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init partition::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init partition::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not init partition::state at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->manager)) {
    std::cerr << "Could not init partition::manager at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->nodes)) {
    std::cerr << "Could not init partition::nodes at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->partitions)) {
    std::cerr << "Could not init partition::partitions at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not init partition::hooks at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->scheduler)) {
    std::cerr << "Could not init partition::scheduler at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->jobs_per_node)) {
    std::cerr << "Could not init partition::jobs_per_node at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not init partition::resources at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_tuple_atom_buff(buf, index, this->properties)) {
    std::cerr << "Could not init partition::properties at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->subdivision)) {
    std::cerr << "Could not init partition::subdivision at pos 13: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->subdivision_id)) {
    std::cerr << "Could not init partition::subdivision_id at pos 14: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->created)) {
    std::cerr << "Could not init partition::created at pos 15: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->updated)) {
    std::cerr << "Could not init partition::updated at pos 16: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->external_id)) {
    std::cerr << "Could not init partition::external_id at pos 17: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_map(buf, index, this->addresses)) {
    std::cerr << "Could not init partition::addresses at pos 18: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init partition::comment at pos 19: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init partition::revision at pos 20: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

void SwmPartition::set_properties(const std::vector<SwmTupleAtomBuff> &new_val) {
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

void SwmPartition::set_addresses(const char* new_val) {
  addresses = const_cast<char*>(new_val);
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

std::vector<SwmTupleAtomBuff> SwmPartition::get_properties() const {
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

char* SwmPartition::get_addresses() const {
  return addresses;
}

std::string SwmPartition::get_comment() const {
  return comment;
}

uint64_t SwmPartition::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_partition(const char *buf, int &index, std::vector<SwmPartition> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a partition list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for partition at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (int i=0; i<list_size; ++i) {
    int entry_size = 0;
    int sub_term_type = 0;
    const int parsed = ei_get_type(buf, &index, &sub_term_type, &entry_size);
    if (parsed < 0) {
      std::cerr << "Could not get term type at position " << index << std::endl;
      return -1;
    }
    switch (sub_term_type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << ") is not a tuple" << std::endl;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_partition(const char* buf, int &index, SwmPartition &obj) {
  obj = SwmPartition(buf, index);
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

