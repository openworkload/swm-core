
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmGlobal:SwmEntity {

 public:
  SwmGlobal();
  SwmGlobal(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_name(const std::string&);
  void set_value(const std::string&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_name() const;
  std::string get_value() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string name;
  std::string value;
  std::string comment;
  uint64_t revision;

};

int eterm_to_global(ETERM*, int, std::vector<SwmGlobal>&);
int eterm_to_global(ETERM*, SwmGlobal&);

} // namespace swm
