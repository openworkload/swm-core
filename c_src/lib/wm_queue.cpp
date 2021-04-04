

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_queue.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmQueue::SwmQueue() {
}

SwmQueue::SwmQueue(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmQueue: empty" << std::endl;
    return;
  }
  if(eterm_to_uint64_t(term, 2, id)) {
    std::cerr << "Could not initialize queue paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize queue paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 4, state)) {
    std::cerr << "Could not initialize queue paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, jobs)) {
    std::cerr << "Could not initialize queue paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, nodes)) {
    std::cerr << "Could not initialize queue paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, users)) {
    std::cerr << "Could not initialize queue paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, admins)) {
    std::cerr << "Could not initialize queue paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 9, hooks)) {
    std::cerr << "Could not initialize queue paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_int64_t(term, 10, priority)) {
    std::cerr << "Could not initialize queue paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 11, comment)) {
    std::cerr << "Could not initialize queue paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 12, revision)) {
    std::cerr << "Could not initialize queue paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmQueue::set_id(const uint64_t &new_val) {
  id = new_val;
}

void SwmQueue::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmQueue::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmQueue::set_jobs(const std::vector<std::string> &new_val) {
  jobs = new_val;
}

void SwmQueue::set_nodes(const std::vector<std::string> &new_val) {
  nodes = new_val;
}

void SwmQueue::set_users(const std::vector<std::string> &new_val) {
  users = new_val;
}

void SwmQueue::set_admins(const std::vector<std::string> &new_val) {
  admins = new_val;
}

void SwmQueue::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmQueue::set_priority(const int64_t &new_val) {
  priority = new_val;
}

void SwmQueue::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmQueue::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

uint64_t SwmQueue::get_id() const {
  return id;
}

std::string SwmQueue::get_name() const {
  return name;
}

std::string SwmQueue::get_state() const {
  return state;
}

std::vector<std::string> SwmQueue::get_jobs() const {
  return jobs;
}

std::vector<std::string> SwmQueue::get_nodes() const {
  return nodes;
}

std::vector<std::string> SwmQueue::get_users() const {
  return users;
}

std::vector<std::string> SwmQueue::get_admins() const {
  return admins;
}

std::vector<std::string> SwmQueue::get_hooks() const {
  return hooks;
}

int64_t SwmQueue::get_priority() const {
  return priority;
}

std::string SwmQueue::get_comment() const {
  return comment;
}

uint64_t SwmQueue::get_revision() const {
  return revision;
}


int swm::eterm_to_queue(ETERM* term, int pos, std::vector<SwmQueue> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a queue list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmQueue(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_queue(ETERM* eterm, SwmQueue &obj) {
  obj = SwmQueue(eterm);
  return 0;
}


void SwmQueue::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << state << separator;
  if(jobs.empty()) {
    std::cerr << prefix << "jobs: []" << separator;
  } else {
    std::cerr << prefix << "jobs" << ": [";
    for(const auto &q: jobs) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for(const auto &q: nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
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


