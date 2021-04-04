
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_resource.h"

namespace swm {

class SwmResource:SwmEntity {

 public:
  SwmResource();
  SwmResource(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_name(const std::string&);
  void set_count(const uint64_t&);
  void set_hooks(const std::vector<std::string>&);
  void set_properties(const std::vector<SwmTupleAtomEterm>&);
  void set_prices(const ETERM*&);
  void set_usage_time(const uint64_t&);
  void set_resources(const std::vector<SwmResource>&);

  std::string get_name() const;
  uint64_t get_count() const;
  std::vector<std::string> get_hooks() const;
  std::vector<SwmTupleAtomEterm> get_properties() const;
  ETERM* get_prices() const;
  uint64_t get_usage_time() const;
  std::vector<SwmResource> get_resources() const;

 private:
  std::string name;
  uint64_t count;
  std::vector<std::string> hooks;
  std::vector<SwmTupleAtomEterm> properties;
  ETERM* prices;
  uint64_t usage_time;
  std::vector<SwmResource> resources;

};

int eterm_to_resource(ETERM*, int, std::vector<SwmResource>&);
int eterm_to_resource(ETERM*, SwmResource&);

} // namespace swm
