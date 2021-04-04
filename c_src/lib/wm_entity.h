
#pragma once

#include <string>

namespace swm {

class SwmEntity {
  public:
    virtual void print(const std::string &prefix, const char separator) const = 0;
};

} // namespace swm
