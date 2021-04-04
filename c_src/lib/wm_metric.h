
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmMetric:SwmEntity {

 public:
  SwmMetric();
  SwmMetric(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_name(const std::string&);
  void set_value_integer(const uint64_t&);
  void set_value_float64(const double&);

  std::string get_name() const;
  uint64_t get_value_integer() const;
  double get_value_float64() const;

 private:
  std::string name;
  uint64_t value_integer;
  double value_float64;

};

int eterm_to_metric(ETERM*, int, std::vector<SwmMetric>&);
int eterm_to_metric(ETERM*, SwmMetric&);

} // namespace swm
