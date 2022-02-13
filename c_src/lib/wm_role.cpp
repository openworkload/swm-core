#include "wm_entity_utils.h"

#include <iostream>

#include "wm_role.h"

#include <ei.h>


using namespace swm;


SwmRole::SwmRole() {
}

SwmRole::SwmRole(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmRole: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmRole header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not initialize role property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize role property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->services)) {
    std::cerr << "Could not initialize role property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize role property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize role property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

}



void SwmRole::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmRole::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmRole::set_services(const std::vector<uint64_t> &new_val) {
  services = new_val;
}

void SwmRole::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmRole::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmRole::get_id() const {
  return id;
}

std::string SwmRole::get_name() const {
  return name;
}

std::vector<uint64_t> SwmRole::get_services() const {
  return services;
}

std::string SwmRole::get_comment() const {
  return comment;
}

uint64_t SwmRole::get_revision() const {
  return revision;
}


int swm::ei_buffer_to_role(const char* buf, const int pos, std::vector<SwmRole> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a role list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for role at position " << pos << std::endl;
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
    array.push_back(SwmRole(term));
  }
  return 0;
}


int swm::eterm_to_role(char* buf, SwmRole &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << role << std::endl;
    return -1;
  }
  obj = SwmRole(eterm);
  return 0;
}


void SwmRole::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
  if (services.empty()) {
    std::cerr << prefix << "services: []" << separator;
  } else {
    std::cerr << prefix << "services" << ": [";
    for (const auto &q: services) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


