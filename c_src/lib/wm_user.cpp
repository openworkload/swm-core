#include "wm_entity_utils.h"

#include <iostream>

#include "wm_user.h"

#include <ei.h>


using namespace swm;


SwmUser::SwmUser() {
}

SwmUser::SwmUser(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmUser: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could decode SwmUser header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmUser term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init user::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init user::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->acl)) {
    std::cerr << "Could not init user::acl at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->groups)) {
    std::cerr << "Could not init user::groups at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->projects)) {
    std::cerr << "Could not init user::projects at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->priority)) {
    std::cerr << "Could not init user::priority at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init user::comment at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init user::revision at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_user(const char *buf, int &index, std::vector<SwmUser> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a user list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for user at position " << index << std::endl;
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

int swm::ei_buffer_to_user(const char* buf, int &index, SwmUser &obj) {
  obj = SwmUser(buf, index);
  return 0;
}

void SwmUser::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << acl << separator;
  if (groups.empty()) {
    std::cerr << prefix << "groups: []" << separator;
  } else {
    std::cerr << prefix << "groups" << ": [";
    for (const auto &q: groups) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (projects.empty()) {
    std::cerr << prefix << "projects: []" << separator;
  } else {
    std::cerr << prefix << "projects" << ": [";
    for (const auto &q: projects) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << priority << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}

