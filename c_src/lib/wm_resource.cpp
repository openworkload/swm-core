#include "wm_entity_utils.h"

#include <iostream>

#include "wm_resource.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmResource::SwmResource() {
}

SwmResource::SwmResource(const char* buf, int* index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmResource: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmResource header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize resource property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->count)) {
    std::cerr << "Could not initialize resource property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not initialize resource property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_tuple_atom_eterm(buf, index, this->properties)) {
    std::cerr << "Could not initialize resource property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_eterm(buf, index, this->prices)) {
    std::cerr << "Could not initialize resource property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->usage_time)) {
    std::cerr << "Could not initialize resource property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not initialize resource property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
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
  prices = new_val;
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

int swm::ei_buffer_to_resource(const char *buf, const int *index, std::vector<SwmResource> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a resource list at position " << index << std::endl;
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

void SwmResource::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << count << separator;
  if (hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for (const auto &q: hooks) {
      std::cerr << q << ",";
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
    std::cerr << prefix << prices << separator;
    std::cerr << prefix << usage_time << separator;
  if (resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for (const auto &q: resources) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  std::cerr << std::endl;
}

