#include "wm_entity_utils.h"

#include <iostream>

#include "wm_project.h"

#include <ei.h>


using namespace swm;


SwmProject::SwmProject() {
}

SwmProject::SwmProject(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmProject: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmProject header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->id)) {
    std::cerr << "Could not initialize project property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize project property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->acl)) {
    std::cerr << "Could not initialize project property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not initialize project property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->priority)) {
    std::cerr << "Could not initialize project property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize project property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize project property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
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


int swm::ei_buffer_to_project(const char* buf, const int pos, std::vector<SwmProject> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a project list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for project at position " << pos << std::endl;
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
    array.push_back(SwmProject(term));
  }
  return 0;
}


int swm::eterm_to_project(char* buf, SwmProject &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << project << std::endl;
    return -1;
  }
  obj = SwmProject(eterm);
  return 0;
}


void SwmProject::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << acl << separator;
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


