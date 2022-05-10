
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_resource.h"

namespace swm {

class SwmNode:SwmEntity {

 public:
  SwmNode();
  SwmNode(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_host(const std::string&);
  void set_api_port(const uint64_t&);
  void set_parent(const std::string&);
  void set_state_power(const std::string&);
  void set_state_alloc(const std::string&);
  void set_roles(const std::vector<uint64_t>&);
  void set_resources(const std::vector<SwmResource>&);
  void set_properties(const std::vector<SwmTupleAtomBuff>&);
  void set_subdivision(const std::string&);
  void set_subdivision_id(const std::string&);
  void set_malfunctions(const std::vector<uint64_t>&);
  void set_comment(const std::string&);
  void set_remote_id(const std::string&);
  void set_is_template(const std::string&);
  void set_gateway(const std::string&);
  void set_prices(const char*);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_host() const;
  uint64_t get_api_port() const;
  std::string get_parent() const;
  std::string get_state_power() const;
  std::string get_state_alloc() const;
  std::vector<uint64_t> get_roles() const;
  std::vector<SwmResource> get_resources() const;
  std::vector<SwmTupleAtomBuff> get_properties() const;
  std::string get_subdivision() const;
  std::string get_subdivision_id() const;
  std::vector<uint64_t> get_malfunctions() const;
  std::string get_comment() const;
  std::string get_remote_id() const;
  std::string get_is_template() const;
  std::string get_gateway() const;
  char* get_prices() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string host;
  uint64_t api_port;
  std::string parent;
  std::string state_power;
  std::string state_alloc;
  std::vector<uint64_t> roles;
  std::vector<SwmResource> resources;
  std::vector<SwmTupleAtomBuff> properties;
  std::string subdivision;
  std::string subdivision_id;
  std::vector<uint64_t> malfunctions;
  std::string comment;
  std::string remote_id;
  std::string is_template;
  std::string gateway;
  char* prices;
  uint64_t revision;

};

int ei_buffer_to_node(const char*, int&, std::vector<SwmNode>&);
int ei_buffer_to_node(const char*, int&, SwmNode&);

} // namespace swm
