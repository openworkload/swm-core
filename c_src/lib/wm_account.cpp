#include "wm_entity_utils.h"

#include <iostream>

#include "wm_account.h"

#include <ei.h>


using namespace swm;


SwmAccount::SwmAccount() {
}

SwmAccount::SwmAccount(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmAccount: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmAccount header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not initialize account property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->name)) {
    std::cerr << "Could not initialize account property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->price_list)) {
    std::cerr << "Could not initialize account property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->users)) {
    std::cerr << "Could not initialize account property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->admins)) {
    std::cerr << "Could not initialize account property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize account property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize account property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

}



void SwmAccount::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmAccount::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmAccount::set_price_list(const std::string &new_val) {
  price_list = new_val;
}

void SwmAccount::set_users(const std::vector<std::string> &new_val) {
  users = new_val;
}

void SwmAccount::set_admins(const std::vector<std::string> &new_val) {
  admins = new_val;
}

void SwmAccount::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmAccount::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmAccount::get_id() const {
  return id;
}

std::string SwmAccount::get_name() const {
  return name;
}

std::string SwmAccount::get_price_list() const {
  return price_list;
}

std::vector<std::string> SwmAccount::get_users() const {
  return users;
}

std::vector<std::string> SwmAccount::get_admins() const {
  return admins;
}

std::string SwmAccount::get_comment() const {
  return comment;
}

uint64_t SwmAccount::get_revision() const {
  return revision;
}


int swm::ei_buffer_to_account(const char* buf, const int pos, std::vector<SwmAccount> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a account list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for account at position " << pos << std::endl;
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
    array.push_back(SwmAccount(term));
  }
  return 0;
}


int swm::eterm_to_account(char* buf, SwmAccount &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << account << std::endl;
    return -1;
  }
  obj = SwmAccount(eterm);
  return 0;
}


void SwmAccount::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << price_list << separator;
  if (users.empty()) {
    std::cerr << prefix << "users: []" << separator;
  } else {
    std::cerr << prefix << "users" << ": [";
    for (const auto &q: users) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (admins.empty()) {
    std::cerr << prefix << "admins: []" << separator;
  } else {
    std::cerr << prefix << "admins" << ": [";
    for (const auto &q: admins) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


