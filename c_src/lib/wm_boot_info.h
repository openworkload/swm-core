
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmBootInfo:SwmEntity {

 public:
  SwmBootInfo();
  SwmBootInfo(const char*);

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

int ei_buffer_to_boot_info(const char*, int, std::vector<SwmBootInfo>&);
int ei_buffer_to_boot_info(const char*, SwmBootInfo&);

} // namespace swm
