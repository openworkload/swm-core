

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_account.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmAccount::SwmAccount() {
}

SwmAccount::SwmAccount(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmAccount: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize account paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 3, name)) {
    std::cerr << "Could not initialize account paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, price_list)) {
    std::cerr << "Could not initialize account paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, users)) {
    std::cerr << "Could not initialize account paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, admins)) {
    std::cerr << "Could not initialize account paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, comment)) {
    std::cerr << "Could not initialize account paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 8, revision)) {
    std::cerr << "Could not initialize account paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
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


int swm::eterm_to_account(ETERM* term, int pos, std::vector<SwmAccount> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a account list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmAccount(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_account(ETERM* eterm, SwmAccount &obj) {
  obj = SwmAccount(eterm);
  return 0;
}


void SwmAccount::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << price_list << separator;
  if(users.empty()) {
    std::cerr << prefix << "users: []" << separator;
  } else {
    std::cerr << prefix << "users" << ": [";
    for(const auto &q: users) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(admins.empty()) {
    std::cerr << prefix << "admins: []" << separator;
  } else {
    std::cerr << prefix << "admins" << ": [";
    for(const auto &q: admins) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


