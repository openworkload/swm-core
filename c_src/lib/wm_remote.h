
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmRemote:SwmEntity {

 public:
  SwmRemote();
  SwmRemote(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_account_id(const std::string&);
  void set_default_image_id(const std::string&);
  void set_name(const std::string&);
  void set_kind(const std::string&);
  void set_server(const std::string&);
  void set_port(const uint64_t&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_account_id() const;
  std::string get_default_image_id() const;
  std::string get_name() const;
  std::string get_kind() const;
  std::string get_server() const;
  uint64_t get_port() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string account_id;
  std::string default_image_id;
  std::string name;
  std::string kind;
  std::string server;
  uint64_t port;
  uint64_t revision;

};

int eterm_to_remote(ETERM*, int, std::vector<SwmRemote>&);
int eterm_to_remote(ETERM*, SwmRemote&);

} // namespace swm
