

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_project.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmProject::SwmProject() {
}

SwmProject::SwmProject(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmProject: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize project paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize project paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, acl)) {
    std::cerr << "Could not initialize project paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, hooks)) {
    std::cerr << "Could not initialize project paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 6, priority)) {
    std::cerr << "Could not initialize project paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, comment)) {
    std::cerr << "Could not initialize project paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 8, revision)) {
    std::cerr << "Could not initialize project paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmProject::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmProject::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmProject::set_acl(const std::string &new_val) {
  acl = new_val;
}

void SwmProject::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmProject::set_priority(const int64_t &new_val) {
  priority = new_val;
}

void SwmProject::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmProject::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmProject::get_id() const {
  return id;
}

std::string SwmProject::get_name() const {
  return name;
}

std::string SwmProject::get_acl() const {
  return acl;
}

std::vector<std::string> SwmProject::get_hooks() const {
  return hooks;
}

int64_t SwmProject::get_priority() const {
  return priority;
}

std::string SwmProject::get_comment() const {
  return comment;
}

uint64_t SwmProject::get_revision() const {
  return revision;
}


int swm::eterm_to_project(ETERM* term, int pos, std::vector<SwmProject> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a project list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmProject(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_project(ETERM* eterm, SwmProject &obj) {
  obj = SwmProject(eterm);
  return 0;
}


void SwmProject::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << acl << separator;
  if(hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for(const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << priority << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


