
#include "wm_entity.h"
#include "wm_porter_data.h"
#include "wm_io.h"

#define BUF_SIZE 32

using namespace swm;


int swm::get_porter_data(std::istream* input, byte* data[]) {
  swm_logd("Get porter input data");
  byte command;
  if(!swm_read_exact(input, &command, 1)) {
    std::cerr << "Could not read command" << std::endl;
    return -1;
  }
  if(command != SWM_COMMAND_PORTER_RUN) {
    std::cerr << "Unknown command: " << command << std::endl;
    return -1;
  }

  byte total = 0;
  if(!swm_read_exact(input, &total, 1)) {
    std::cerr << "Could not read total data count" << std::endl;
    return -1;
  }
  if(total != SWM_DATA_TYPES_COUNT) {
    std::cerr << "Incorrect data types count: " << total << std::endl;
    return -1;
  }

  for(unsigned short i=0; i<SWM_DATA_TYPES_COUNT; ++i) {

    byte type = 0;
    if(!swm_read_exact(input, &type, 1)) {
      std::cerr << "Could not read data type (i=" << i << ")" << std::endl;
      return -1;
    }

    uint32_t len = 0;
    if(!swm_read_length(input, &len)) {
      std::cerr << "Data length is 0 (type=" << type << ")" << std::endl;
      return -1;
    }
    swm_logd("Data length is %zu (type=%d)", len, type);

    data[i] = (byte*)malloc(len);
    if(!data[i]) {
      std::cerr << "Could not allocate " << len << " bytes for data type " << type << std::endl;
      return -1;
    }

    unsigned int read_bytes = 0;
    for(unsigned int marker=0; marker<len; marker+=BUF_SIZE) {
      if(marker+BUF_SIZE<len) {
        read_bytes = BUF_SIZE;
      } else {
        read_bytes = len-marker;
      }
      if(!swm_read_exact(input, data[i]+marker, read_bytes)) {
        std::cerr << "Couldn't get " << read_bytes << " bytes of data type " << type << std::endl;
        return -1;
      }
    }
  }

  return 0;
}

int swm::parse_data(byte *data[], SwmProcInfo &info) {
  for(size_t i=0; i<SWM_DATA_TYPES_COUNT; ++i) {
    if(!data[i]) {
      continue;
    }
    ETERM* term = erl_decode(data[i]);
    if(!term) {
      std::cerr << "Could not decode job input data of type " << i << std::endl;
      return -1;
    }
    switch(i) {
      case SWM_DATA_TYPE_JOBS: {
        info.job = SwmJob(term);
        break;
      };
      case SWM_DATA_TYPE_USERS: {
        info.user = SwmUser(term);
        break;
      };
      default: {
        std::cerr << "Unknown data type: " << i << std::endl;
        return -1;
      }
    }
  }
  return 0;
}

