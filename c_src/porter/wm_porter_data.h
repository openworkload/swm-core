#pragma once

#include <iostream>

#include "wm_job.h"
#include "wm_user.h"
#include "wm_porter_types.h"


namespace swm {

struct SwmProcInfo {
  SwmJob job;
  SwmUser user;
};

int get_porter_data(std::istream* input, byte* data[]);
int parse_data(byte *data[], SwmProcInfo &info);

}  // namespace swm
