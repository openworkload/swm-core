#pragma once

#include <iostream>

#include "wm_job.h"
#include "wm_user.h"

#define SWM_DATA_TYPES_COUNT 2

#define SWM_DATA_TYPE_USERS 0
#define SWM_DATA_TYPE_JOBS 1

#define SWM_COMMAND_PORTER_RUN 1

typedef uint8_t byte;

namespace swm {

struct SwmProcInfo {
  SwmJob job;
  SwmUser user;
};

int get_porter_data(std::istream* input, byte* data[]);
int parse_data(byte *data[], SwmProcInfo &info);

}
