#include "wm_entity_utils.h"

#include <iostream>

#include "wm_grid.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmGrid::SwmGrid() {
}

SwmGrid::SwmGrid(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmGrid: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmGrid header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmGrid term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init grid::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init grid::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not init grid::state at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->manager)) {
    std::cerr << "Could not init grid::manager at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->clusters)) {
    std::cerr << "Could not init grid::clusters at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not init grid::hooks at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->scheduler)) {
    std::cerr << "Could not init grid::scheduler at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not init grid::resources at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_tuple_atom_eterm(buf, index, this->properties)) {
    std::cerr << "Could not init grid::properties at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init grid::comment at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init grid::revision at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmGrid::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmGrid::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmGrid::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmGrid::set_manager(const std::string &new_val) {
  manager = new_val;
}

void SwmGrid::set_clusters(const std::vector<std::string> &new_val) {
  clusters = new_val;
}

void SwmGrid::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmGrid::set_scheduler(const uint64_t &new_val) {
  scheduler = new_val;
}

void SwmGrid::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

void SwmGrid::set_properties(const std::vector<SwmTupleAtomEterm> &new_val) {
  properties = new_val;
}

void SwmGrid::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmGrid::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmGrid::get_id() const {
  return id;
}

std::string SwmGrid::get_name() const {
  return name;
}

std::string SwmGrid::get_state() const {
  return state;
}

std::string SwmGrid::get_manager() const {
  return manager;
}

std::vector<std::string> SwmGrid::get_clusters() const {
  return clusters;
}

std::vector<std::string> SwmGrid::get_hooks() const {
  return hooks;
}

uint64_t SwmGrid::get_scheduler() const {
  return scheduler;
}

std::vector<SwmResource> SwmGrid::get_resources() const {
  return resources;
}

std::vector<SwmTupleAtomEterm> SwmGrid::get_properties() const {
  return properties;
}

std::string SwmGrid::get_comment() const {
  return comment;
}

uint64_t SwmGrid::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_grid(const char *buf, int &index, std::vector<SwmGrid> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a grid list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for grid at position " << index << std::endl;
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

int swm::ei_buffer_to_grid(const char* buf, int &index, SwmGrid &obj) {
  obj = SwmGrid(buf, index);
  return 0;
}

void SwmGrid::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
    std::cerr << prefix << manager << separator;
  if (clusters.empty()) {
    std::cerr << prefix << "clusters: []" << separator;
  } else {
    std::cerr << prefix << "clusters" << ": [";
    for (const auto &q: clusters) {
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

