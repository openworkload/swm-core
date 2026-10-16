
#pragma once

#include <cstdint>
#include <string>

namespace swm {

class SwmEntity {
 public:
  virtual ~SwmEntity() = default;
  virtual void print(const std::string &prefix, const char separator) const = 0;
};

}  // namespace swm
