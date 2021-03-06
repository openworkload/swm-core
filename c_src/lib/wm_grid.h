
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_resource.h"

namespace swm {

class SwmGrid:SwmEntity {

 public:
  SwmGrid();
  SwmGrid(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_state(const std::string&);
  void set_manager(const std::string&);
  void set_clusters(const std::vector<std::string>&);
  void set_hooks(const std::vector<std::string>&);
  void set_scheduler(const uint64_t&);
  void set_resources(const std::vector<SwmResource>&);
  void set_properties(const std::vector<SwmTupleAtomBuff>&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_state() const;
  std::string get_manager() const;
  std::vector<std::string> get_clusters() const;
  std::vector<std::string> get_hooks() const;
  uint64_t get_scheduler() const;
  std::vector<SwmResource> get_resources() const;
  std::vector<SwmTupleAtomBuff> get_properties() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string state;
  std::string manager;
  std::vector<std::string> clusters;
  std::vector<std::string> hooks;
  uint64_t scheduler;
  std::vector<SwmResource> resources;
  std::vector<SwmTupleAtomBuff> properties;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_grid(const char*, int&, std::vector<SwmGrid>&);
int ei_buffer_to_grid(const char*, int&, SwmGrid&);

} // namespace swm
