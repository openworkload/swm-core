
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmImage:SwmEntity {

 public:
  SwmImage();
  SwmImage(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_name(const std::string&);
  void set_id(const std::string&);
  void set_tags(const std::vector<std::string>&);
  void set_size(const uint64_t&);
  void set_kind(const std::string&);
  void set_status(const std::string&);
  void set_remote_id(const std::string&);
  void set_created(const std::string&);
  void set_updated(const std::string&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_name() const;
  std::string get_id() const;
  std::vector<std::string> get_tags() const;
  uint64_t get_size() const;
  std::string get_kind() const;
  std::string get_status() const;
  std::string get_remote_id() const;
  std::string get_created() const;
  std::string get_updated() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string name;
  std::string id;
  std::vector<std::string> tags;
  uint64_t size;
  std::string kind;
  std::string status;
  std::string remote_id;
  std::string created;
  std::string updated;
  std::string comment;
  uint64_t revision;

};

int eterm_to_image(ETERM*, int, std::vector<SwmImage>&);
int eterm_to_image(ETERM*, SwmImage&);

} // namespace swm
