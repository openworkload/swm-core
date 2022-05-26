#include <iostream>

#include "wm_queue.h"

#include <ei.h>


using namespace swm;


SwmQueue::SwmQueue() {
}

SwmQueue::SwmQueue(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmQueue: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmQueue header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmQueue term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not init queue::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init queue::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->state)) {
    std::cerr << "Could not init queue::state at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->jobs)) {
    std::cerr << "Could not init queue::jobs at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->nodes)) {
    std::cerr << "Could not init queue::nodes at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->users)) {
    std::cerr << "Could not init queue::users at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->admins)) {
    std::cerr << "Could not init queue::admins at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not init queue::hooks at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->priority)) {
    std::cerr << "Could not init queue::priority at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init queue::comment at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init queue::revision at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_queue(const char *buf, int &index, std::vector<SwmQueue> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a queue list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for queue at position " << index << std::endl;
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

int swm::ei_buffer_to_queue(const char* buf, int &index, SwmQueue &obj) {
  obj = SwmQueue(buf, index);
  return 0;
}

void SwmQueue::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << id << separator;
  std::cerr << prefix << name << separator;
  std::cerr << prefix << state << separator;
  if (jobs.empty()) {
    std::cerr << prefix << "jobs: []" << separator;
  } else {
    std::cerr << prefix << "jobs" << ": [";
    for (const auto &q: jobs) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for (const auto &q: nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
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
  if (hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for (const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << prefix << priority << separator;
  std::cerr << prefix << comment << separator;
  std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

