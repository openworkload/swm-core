
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmBootInfo:SwmEntity {

 public:
  SwmBootInfo();
  SwmBootInfo(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_node_host(const std::string&);
  void set_node_port(const uint64_t&);
  void set_parent_host(const std::string&);
  void set_parent_port(const uint64_t&);

  std::string get_node_host() const;
  uint64_t get_node_port() const;
  std::string get_parent_host() const;
  uint64_t get_parent_port() const;

 private:
  std::string node_host;
  uint64_t node_port;
  std::string parent_host;
  uint64_t parent_port;

};

int eterm_to_boot_info(ETERM*, int, std::vector<SwmBootInfo>&);
int eterm_to_boot_info(ETERM*, SwmBootInfo&);

} // namespace swm
