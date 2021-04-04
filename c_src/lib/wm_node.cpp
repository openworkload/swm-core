

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_node.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmNode::SwmNode() {
}

SwmNode::SwmNode(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmNode: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize node paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize node paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, host)) {
    std::cerr << "Could not initialize node paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, api_port)) {
    std::cerr << "Could not initialize node paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, parent)) {
    std::cerr << "Could not initialize node paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 7, state_power)) {
    std::cerr << "Could not initialize node paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 8, state_alloc)) {
    std::cerr << "Could not initialize node paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 9, roles)) {
    std::cerr << "Could not initialize node paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 10, resources)) {
    std::cerr << "Could not initialize node paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_atom_eterm(term, 11, properties)) {
    std::cerr << "Could not initialize node paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 12, subdivision)) {
    std::cerr << "Could not initialize node paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 13, subdivision_id)) {
    std::cerr << "Could not initialize node paremeter at position 13" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 14, malfunctions)) {
    std::cerr << "Could not initialize node paremeter at position 14" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 15, comment)) {
    std::cerr << "Could not initialize node paremeter at position 15" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 16, remote_id)) {
    std::cerr << "Could not initialize node paremeter at position 16" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 17, is_template)) {
    std::cerr << "Could not initialize node paremeter at position 17" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 18, gateway)) {
    std::cerr << "Could not initialize node paremeter at position 18" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_eterm(term, 19, prices)) {
    std::cerr << "Could not initialize node paremeter at position 19" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 20, revision)) {
    std::cerr << "Could not initialize node paremeter at position 20" << std::endl;
    erl_print_term(stderr, term);
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

void SwmNode::set_properties(const std::vector<SwmTupleAtomEterm> &new_val) {
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

void SwmNode::set_prices(const ETERM* &new_val) {
  prices = const_cast<ETERM*>(new_val);
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

std::vector<SwmTupleAtomEterm> SwmNode::get_properties() const {
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

ETERM* SwmNode::get_prices() const {
  return prices;
}

uint64_t SwmNode::get_revision() const {
  return revision;
}


int swm::eterm_to_node(ETERM* term, int pos, std::vector<SwmNode> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a node list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmNode(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_node(ETERM* eterm, SwmNode &obj) {
  obj = SwmNode(eterm);
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
  if(roles.empty()) {
    std::cerr << prefix << "roles: []" << separator;
  } else {
    std::cerr << prefix << "roles" << ": [";
    for(const auto &q: roles) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
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
  if(malfunctions.empty()) {
    std::cerr << prefix << "malfunctions: []" << separator;
  } else {
    std::cerr << prefix << "malfunctions" << ": [";
    for(const auto &q: malfunctions) {
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


