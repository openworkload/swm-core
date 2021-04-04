

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_credential.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmCredential::SwmCredential() {
}

SwmCredential::SwmCredential(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmCredential: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize credential paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, remote_id)) {
    std::cerr << "Could not initialize credential paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, tenant_name)) {
    std::cerr << "Could not initialize credential paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, tenant_domain_name)) {
    std::cerr << "Could not initialize credential paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, username)) {
    std::cerr << "Could not initialize credential paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, password)) {
    std::cerr << "Could not initialize credential paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, key_name)) {
    std::cerr << "Could not initialize credential paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 9, revision)) {
    std::cerr << "Could not initialize credential paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmCredential::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmCredential::set_remote_id(const std::string &new_val) {
  remote_id = new_val;
}

void SwmCredential::set_tenant_name(const std::string &new_val) {
  tenant_name = new_val;
}

void SwmCredential::set_tenant_domain_name(const std::string &new_val) {
  tenant_domain_name = new_val;
}

void SwmCredential::set_username(const std::string &new_val) {
  username = new_val;
}

void SwmCredential::set_password(const std::string &new_val) {
  password = new_val;
}

void SwmCredential::set_key_name(const std::string &new_val) {
  key_name = new_val;
}

void SwmCredential::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmCredential::get_id() const {
  return id;
}

std::string SwmCredential::get_remote_id() const {
  return remote_id;
}

std::string SwmCredential::get_tenant_name() const {
  return tenant_name;
}

std::string SwmCredential::get_tenant_domain_name() const {
  return tenant_domain_name;
}

std::string SwmCredential::get_username() const {
  return username;
}

std::string SwmCredential::get_password() const {
  return password;
}

std::string SwmCredential::get_key_name() const {
  return key_name;
}

uint64_t SwmCredential::get_revision() const {
  return revision;
}


int swm::eterm_to_credential(ETERM* term, int pos, std::vector<SwmCredential> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a credential list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmCredential(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_credential(ETERM* eterm, SwmCredential &obj) {
  obj = SwmCredential(eterm);
  return 0;
}


void SwmCredential::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << remote_id << separator;
    std::cerr << prefix << tenant_name << separator;
    std::cerr << prefix << tenant_domain_name << separator;
    std::cerr << prefix << username << separator;
    std::cerr << prefix << password << separator;
    std::cerr << prefix << key_name << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


