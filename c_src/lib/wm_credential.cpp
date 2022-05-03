#include "wm_entity_utils.h"

#include <iostream>

#include "wm_credential.h"

#include <ei.h>


using namespace swm;


SwmCredential::SwmCredential() {
}

SwmCredential::SwmCredential(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmCredential: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmCredential header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmCredential term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init credential::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->remote_id)) {
    std::cerr << "Could not init credential::remote_id at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->tenant_name)) {
    std::cerr << "Could not init credential::tenant_name at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->tenant_domain_name)) {
    std::cerr << "Could not init credential::tenant_domain_name at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->username)) {
    std::cerr << "Could not init credential::username at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->password)) {
    std::cerr << "Could not init credential::password at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->key_name)) {
    std::cerr << "Could not init credential::key_name at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init credential::revision at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_credential(const char *buf, int &index, std::vector<SwmCredential> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a credential list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for credential at position " << index << std::endl;
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

int swm::ei_buffer_to_credential(const char* buf, int &index, SwmCredential &obj) {
  obj = SwmCredential(buf, index);
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

