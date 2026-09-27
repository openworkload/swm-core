#pragma once

#include "wm_job.h"
#include "wm_porter_types.h"
#include "wm_user.h"

#include <iostream>

namespace swm {

struct SwmProcInfo {
  SwmJob job;
  SwmUser user;
};

int get_porter_data(std::istream *input, byte *data[]);
int parse_data(byte *data[], SwmProcInfo &info);

}  // namespace swm
