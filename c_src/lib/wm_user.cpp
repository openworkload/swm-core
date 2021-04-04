

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_user.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmUser::SwmUser() {
}

SwmUser::SwmUser(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmUser: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize user paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize user paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, acl)) {
    std::cerr << "Could not initialize user paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, groups)) {
    std::cerr << "Could not initialize user paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 6, projects)) {
    std::cerr << "Could not initialize user paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 7, priority)) {
    std::cerr << "Could not initialize user paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, comment)) {
    std::cerr << "Could not initialize user paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 9, revision)) {
    std::cerr << "Could not initialize user paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmUser::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmUser::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmUser::set_acl(const std::string &new_val) {
  acl = new_val;
}

void SwmUser::set_groups(const std::vector<uint64_t> &new_val) {
  groups = new_val;
}

void SwmUser::set_projects(const std::vector<uint64_t> &new_val) {
  projects = new_val;
}

void SwmUser::set_priority(const int64_t &new_val) {
  priority = new_val;
}

void SwmUser::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmUser::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmUser::get_id() const {
  return id;
}

std::string SwmUser::get_name() const {
  return name;
}

std::string SwmUser::get_acl() const {
  return acl;
}

std::vector<uint64_t> SwmUser::get_groups() const {
  return groups;
}

std::vector<uint64_t> SwmUser::get_projects() const {
  return projects;
}

int64_t SwmUser::get_priority() const {
  return priority;
}

std::string SwmUser::get_comment() const {
  return comment;
}

uint64_t SwmUser::get_revision() const {
  return revision;
}


int swm::eterm_to_user(ETERM* term, int pos, std::vector<SwmUser> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a user list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmUser(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_user(ETERM* eterm, SwmUser &obj) {
  obj = SwmUser(eterm);
  return 0;
}


void SwmUser::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << acl << separator;
  if(groups.empty()) {
    std::cerr << prefix << "groups: []" << separator;
  } else {
    std::cerr << prefix << "groups" << ": [";
    for(const auto &q: groups) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(projects.empty()) {
    std::cerr << prefix << "projects: []" << separator;
  } else {
    std::cerr << prefix << "projects" << ": [";
    for(const auto &q: projects) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << priority << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


