
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmRelocation:SwmEntity {

 public:
  SwmRelocation();
  SwmRelocation(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::uint64_t&);
  void set_job_id(const std::string&);
  void set_cancaled(const std::string&);

  std::uint64_t get_id() const;
  std::string get_job_id() const;
  std::string get_cancaled() const;

 private:
  std::uint64_t id;
  std::string job_id;
  std::string cancaled;

};

int eterm_to_relocation(ETERM*, int, std::vector<SwmRelocation>&);
int eterm_to_relocation(ETERM*, SwmRelocation&);

} // namespace swm
