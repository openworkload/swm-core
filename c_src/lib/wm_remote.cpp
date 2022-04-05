#include "wm_entity_utils.h"

#include <iostream>

#include "wm_remote.h"

#include <ei.h>


using namespace swm;


SwmRemote::SwmRemote() {
}

SwmRemote::SwmRemote(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmRemote: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmRemote header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not initialize remote property at position=2" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->account_id)) {
    std::cerr << "Could not initialize remote property at position=3" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->default_image_id)) {
    std::cerr << "Could not initialize remote property at position=4" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->default_flavor_id)) {
    std::cerr << "Could not initialize remote property at position=5" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->name)) {
    std::cerr << "Could not initialize remote property at position=6" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->kind)) {
    std::cerr << "Could not initialize remote property at position=7" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->server)) {
    std::cerr << "Could not initialize remote property at position=8" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->port)) {
    std::cerr << "Could not initialize remote property at position=9" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize remote property at position=10" << std::endl;
    ei_print_term(stderr, buf, &index);
    return;
  }

}


void SwmRemote::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmRemote::set_account_id(const std::string &new_val) {
  account_id = new_val;
}

void SwmRemote::set_default_image_id(const std::string &new_val) {
  default_image_id = new_val;
}

void SwmRemote::set_default_flavor_id(const std::string &new_val) {
  default_flavor_id = new_val;
}

void SwmRemote::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmRemote::set_kind(const std::string &new_val) {
  kind = new_val;
}

void SwmRemote::set_server(const std::string &new_val) {
  server = new_val;
}

void SwmRemote::set_port(const uint64_t &new_val) {
  port = new_val;
}

void SwmRemote::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmRemote::get_id() const {
  return id;
}

std::string SwmRemote::get_account_id() const {
  return account_id;
}

std::string SwmRemote::get_default_image_id() const {
  return default_image_id;
}

std::string SwmRemote::get_default_flavor_id() const {
  return default_flavor_id;
}

std::string SwmRemote::get_name() const {
  return name;
}

std::string SwmRemote::get_kind() const {
  return kind;
}

std::string SwmRemote::get_server() const {
  return server;
}

uint64_t SwmRemote::get_port() const {
  return port;
}

uint64_t SwmRemote::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_remote(const char *buf, int &index, std::vector<SwmRemote> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a remote list at position " << index << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for remote at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (int i=0; i<list_size; ++i) {
    int entry_size = 0;
    int type = 0;
    switch (ei_get_type(buf, &index, &type, &entry_size)) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << " is not a tuple: <class 'type'>" << std::endl;
    }
  }

  return 0;
}

void SwmRemote::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << account_id << separator;
    std::cerr << prefix << default_image_id << separator;
    std::cerr << prefix << default_flavor_id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << kind << separator;
    std::cerr << prefix << server << separator;
    std::cerr << prefix << port << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

