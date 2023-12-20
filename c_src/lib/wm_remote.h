
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmRemote:SwmEntity {

 public:
  SwmRemote();
  SwmRemote(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_account_id(const std::string&);
  void set_default_image_id(const std::string&);
  void set_default_flavor_id(const std::string&);
  void set_name(const std::string&);
  void set_kind(const std::string&);
  void set_server(const std::string&);
  void set_port(const uint64_t&);
  void set_runtime(const std::map<std::string, std::string>&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_account_id() const;
  std::string get_default_image_id() const;
  std::string get_default_flavor_id() const;
  std::string get_name() const;
  std::string get_kind() const;
  std::string get_server() const;
  uint64_t get_port() const;
  std::map<std::string, std::string> get_runtime() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string account_id;
  std::string default_image_id;
  std::string default_flavor_id;
  std::string name;
  std::string kind;
  std::string server;
  uint64_t port;
  std::map<std::string, std::string> runtime;
  uint64_t revision;

};

int ei_buffer_to_remote(const char*, int&, std::vector<SwmRemote>&);
int ei_buffer_to_remote(const char*, int&, SwmRemote&);

} // namespace swm
