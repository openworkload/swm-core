#include "wm_entity_utils.h"

#include <iostream>

#include "wm_metric.h"

#include <ei.h>


using namespace swm;


SwmMetric::SwmMetric() {
}

SwmMetric::SwmMetric(const char* buf, int* index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmMetric: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmMetric header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->name)) {
    std::cerr << "Could not initialize metric property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->value_integer)) {
    std::cerr << "Could not initialize metric property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_double(buf, index, this->value_float64)) {
    std::cerr << "Could not initialize metric property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
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

int swm::ei_buffer_to_metric(const char *buf, const int *index, std::vector<SwmMetric> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a metric list at position " << index << std::endl;
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

void SwmMetric::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << value_integer << separator;
    std::cerr << prefix << value_float64 << separator;
  std::cerr << std::endl;
}

