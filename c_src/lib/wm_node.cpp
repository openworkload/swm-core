#include <iostream>

#include "wm_node.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmNode::SwmNode() {
}

SwmNode::SwmNode(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmNode: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmNode header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmNode term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init node::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init node::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->host)) {
    std::cerr << "Could not init node::host at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->api_port)) {
    std::cerr << "Could not init node::api_port at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->parent)) {
    std::cerr << "Could not init node::parent at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state_power)) {
    std::cerr << "Could not init node::state_power at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state_alloc)) {
    std::cerr << "Could not init node::state_alloc at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->roles)) {
    std::cerr << "Could not init node::roles at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not init node::resources at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_tuple_atom_buff(buf, index, this->properties)) {
    std::cerr << "Could not init node::properties at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->subdivision)) {
    std::cerr << "Could not init node::subdivision at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->subdivision_id)) {
    std::cerr << "Could not init node::subdivision_id at pos 13: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->malfunctions)) {
    std::cerr << "Could not init node::malfunctions at pos 14: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init node::comment at pos 15: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->remote_id)) {
    std::cerr << "Could not init node::remote_id at pos 16: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->is_template)) {
    std::cerr << "Could not init node::is_template at pos 17: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->gateway)) {
    std::cerr << "Could not init node::gateway at pos 18: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_map(buf, index, this->prices)) {
    std::cerr << "Could not init node::prices at pos 19: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init node::revision at pos 20: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmNode::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmNode::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmNode::set_host(const std::string &new_val) {
  host = new_val;
}

void SwmNode::set_api_port(const uint64_t &new_val) {
  api_port = new_val;
}

void SwmNode::set_parent(const std::string &new_val) {
  parent = new_val;
}

void SwmNode::set_state_power(const std::string &new_val) {
  state_power = new_val;
}

void SwmNode::set_state_alloc(const std::string &new_val) {
  state_alloc = new_val;
}

void SwmNode::set_roles(const std::vector<uint64_t> &new_val) {
  roles = new_val;
}

void SwmNode::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

void SwmNode::set_properties(const std::vector<SwmTupleAtomBuff> &new_val) {
  properties = new_val;
}

void SwmNode::set_subdivision(const std::string &new_val) {
  subdivision = new_val;
}

void SwmNode::set_subdivision_id(const std::string &new_val) {
  subdivision_id = new_val;
}

void SwmNode::set_malfunctions(const std::vector<uint64_t> &new_val) {
  malfunctions = new_val;
}

void SwmNode::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmNode::set_remote_id(const std::string &new_val) {
  remote_id = new_val;
}

void SwmNode::set_is_template(const std::string &new_val) {
  is_template = new_val;
}

void SwmNode::set_gateway(const std::string &new_val) {
  gateway = new_val;
}

void SwmNode::set_prices(const char* new_val) {
  prices = const_cast<char*>(new_val);
}

void SwmNode::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmNode::get_id() const {
  return id;
}

std::string SwmNode::get_name() const {
  return name;
}

std::string SwmNode::get_host() const {
  return host;
}

uint64_t SwmNode::get_api_port() const {
  return api_port;
}

std::string SwmNode::get_parent() const {
  return parent;
}

std::string SwmNode::get_state_power() const {
  return state_power;
}

std::string SwmNode::get_state_alloc() const {
  return state_alloc;
}

std::vector<uint64_t> SwmNode::get_roles() const {
  return roles;
}

std::vector<SwmResource> SwmNode::get_resources() const {
  return resources;
}

std::vector<SwmTupleAtomBuff> SwmNode::get_properties() const {
  return properties;
}

std::string SwmNode::get_subdivision() const {
  return subdivision;
}

std::string SwmNode::get_subdivision_id() const {
  return subdivision_id;
}

std::vector<uint64_t> SwmNode::get_malfunctions() const {
  return malfunctions;
}

std::string SwmNode::get_comment() const {
  return comment;
}

std::string SwmNode::get_remote_id() const {
  return remote_id;
}

std::string SwmNode::get_is_template() const {
  return is_template;
}

std::string SwmNode::get_gateway() const {
  return gateway;
}

char* SwmNode::get_prices() const {
  return prices;
}

uint64_t SwmNode::get_revision() const {
  return revision;
}

int swm::ei_buffer_to_node(const char *buf, int &index, std::vector<SwmNode> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a node list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for node at position " << index << std::endl;
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

int swm::ei_buffer_to_node(const char* buf, int &index, SwmNode &obj) {
  obj = SwmNode(buf, index);
  return 0;
}

void SwmNode::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << id << separator;
  std::cerr << prefix << name << separator;
  std::cerr << prefix << host << separator;
  std::cerr << prefix << api_port << separator;
  std::cerr << prefix << parent << separator;
  std::cerr << prefix << state_power << separator;
  std::cerr << prefix << state_alloc << separator;
  if (roles.empty()) {
    std::cerr << prefix << "roles: []" << separator;
  } else {
    std::cerr << prefix << "roles" << ": [";
    for (const auto &q: roles) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
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
  if (malfunctions.empty()) {
    std::cerr << prefix << "malfunctions: []" << separator;
  } else {
    std::cerr << prefix << "malfunctions" << ": [";
    for (const auto &q: malfunctions) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << prefix << comment << separator;
  std::cerr << prefix << remote_id << separator;
  std::cerr << prefix << is_template << separator;
  std::cerr << prefix << gateway << separator;
  std::cerr << prefix << prices << separator;
  std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

