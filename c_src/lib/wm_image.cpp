

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_image.h"

#include <erl_interface.h>
#include <ei.h>


using namespace swm;


SwmImage::SwmImage() {
}

SwmImage::SwmImage(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmImage: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, name)) {
    std::cerr << "Could not initialize image paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, id)) {
    std::cerr << "Could not initialize image paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, tags)) {
    std::cerr << "Could not initialize image paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 5, size)) {
    std::cerr << "Could not initialize image paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 6, kind)) {
    std::cerr << "Could not initialize image paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, status)) {
    std::cerr << "Could not initialize image paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, remote_id)) {
    std::cerr << "Could not initialize image paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 9, created)) {
    std::cerr << "Could not initialize image paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 10, updated)) {
    std::cerr << "Could not initialize image paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 11, comment)) {
    std::cerr << "Could not initialize image paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 12, revision)) {
    std::cerr << "Could not initialize image paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmImage::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmImage::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmImage::set_tags(const std::vector<std::string> &new_val) {
  tags = new_val;
}

void SwmImage::set_size(const uint64_t &new_val) {
  size = new_val;
}

void SwmImage::set_kind(const std::string &new_val) {
  kind = new_val;
}

void SwmImage::set_status(const std::string &new_val) {
  status = new_val;
}

void SwmImage::set_remote_id(const std::string &new_val) {
  remote_id = new_val;
}

void SwmImage::set_created(const std::string &new_val) {
  created = new_val;
}

void SwmImage::set_updated(const std::string &new_val) {
  updated = new_val;
}

void SwmImage::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmImage::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmImage::get_name() const {
  return name;
}

std::string SwmImage::get_id() const {
  return id;
}

std::vector<std::string> SwmImage::get_tags() const {
  return tags;
}

uint64_t SwmImage::get_size() const {
  return size;
}

std::string SwmImage::get_kind() const {
  return kind;
}

std::string SwmImage::get_status() const {
  return status;
}

std::string SwmImage::get_remote_id() const {
  return remote_id;
}

std::string SwmImage::get_created() const {
  return created;
}

std::string SwmImage::get_updated() const {
  return updated;
}

std::string SwmImage::get_comment() const {
  return comment;
}

uint64_t SwmImage::get_revision() const {
  return revision;
}


int swm::eterm_to_image(ETERM* term, int pos, std::vector<SwmImage> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a image list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmImage(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_image(ETERM* eterm, SwmImage &obj) {
  obj = SwmImage(eterm);
  return 0;
}


void SwmImage::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << id << separator;
  if(tags.empty()) {
    std::cerr << prefix << "tags: []" << separator;
  } else {
    std::cerr << prefix << "tags" << ": [";
    for(const auto &q: tags) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << size << separator;
    std::cerr << prefix << kind << separator;
    std::cerr << prefix << status << separator;
    std::cerr << prefix << remote_id << separator;
    std::cerr << prefix << created << separator;
    std::cerr << prefix << updated << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


