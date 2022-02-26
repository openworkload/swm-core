#include "wm_entity_utils.h"

#include <iostream>

#include "wm_image.h"

#include <ei.h>


using namespace swm;


SwmImage::SwmImage() {
}

SwmImage::SwmImage(const char* buf, int* index) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmImage: null" << std::endl;
    return;
  }
  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmImage header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not initialize image property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not initialize image property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->tags)) {
    std::cerr << "Could not initialize image property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->size)) {
    std::cerr << "Could not initialize image property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->kind)) {
    std::cerr << "Could not initialize image property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->status)) {
    std::cerr << "Could not initialize image property at position=7" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->remote_id)) {
    std::cerr << "Could not initialize image property at position=8" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->created)) {
    std::cerr << "Could not initialize image property at position=9" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->updated)) {
    std::cerr << "Could not initialize image property at position=10" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize image property at position=11" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not initialize image property at position=12" << std::endl;
    ei_print_term(stderr, buf, index);
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

int swm::ei_buffer_to_image(const char *buf, const int *index, std::vector<SwmImage> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a image list at position " << index << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for " + entity_name + " at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    int entry_size;
    int type;
    int res = ei_get_type(buf, &index, &type, &entry_size);
    switch (type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
      default:
        std::cerr << "List element (at position " << i << " is not a tuple: " << <class 'type'> << std::endl;
    }
  }

  return 0;
}

void SwmImage::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << name << separator;
    std::cerr << prefix << id << separator;
  if (tags.empty()) {
    std::cerr << prefix << "tags: []" << separator;
  } else {
    std::cerr << prefix << "tags" << ": [";
    for (const auto &q: tags) {
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

