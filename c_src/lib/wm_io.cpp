#include <cstring>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "wm_entity.h"
#include "wm_io.h"

#if !defined(WIN32)
#include <unistd.h>
#endif

#define LOG_OUT_STREAM stderr

static int g_log_level = SWM_LOG_LEVEL_INFO;
static FILE *g_log_stream = NULL;

// Need for Erlang libs. They were compiled by old version of VS, while VS 2017
// omits some extern symbols. Probably, this #ifdef need to be removed in future.
#if defined(WIN32) && _MSC_VER >= 1700
FILE _iob[] = { *stdin, *stdout, *stderr };
extern "C" FILE * __cdecl __iob_func(void) {
  return _iob;
}
extern "C" FILE * __cdecl __imp___iob_func(void) {
  return _iob;
}
#endif

void _print_log_format(const char* tag, const char* message, va_list args) {
  time_t now;
  time(&now);
  char *date = ctime(&now);
  date[strlen(date) - 1] = '\0';
  fprintf(LOG_OUT_STREAM, "%s [%s] ", date, tag);
  vfprintf(LOG_OUT_STREAM, message, args);
  fprintf(LOG_OUT_STREAM, "\n");
}

void swm_log_init(int level, FILE *stream) {
  g_log_level = level;
  g_log_stream = stream;
}

int swm_get_log_level() {
  return g_log_level;
}

void swm_logd(const char* message, ...) {
  if(g_log_level < SWM_LOG_LEVEL_DEBUG1) {
    return;
  }
  va_list args;
  va_start(args, message);
  if(message==NULL) {
    fprintf(LOG_OUT_STREAM, "\n");
  } else {
    _print_log_format("DEBUG", message, args);
  }
  va_end(args);
  fflush(LOG_OUT_STREAM);
}

void swm_logdd(const char* message, ...) {
  if(g_log_level < SWM_LOG_LEVEL_DEBUG2) {
    return;
  }
  va_list args;
  va_start(args, message);
  _print_log_format("DEBUG2", message, args);
  va_end(args);
}

bool swm_read_length(std::istream *stream, uint32_t *len) {
  // swm_read_exact() will check stream for nullptr
  uint8_t buf[4];
  if (!swm_read_exact(stream, buf, 4)) {
    return false;
  }

  // Convert 4 bytes to unsigned long:
  *len = (buf[0] << 24) |
         (buf[1] << 16) |
         (buf[2] << 8)  |
          buf[3];
  return true;
}

bool swm_read_exact(std::istream *stream, uint8_t *buf, size_t len) {
  if (stream == nullptr) {
    throw std::runtime_error("swm_read_exact(): \"stream\" cannot be equal to nullptr");
  }

  stream->read((char *)buf, len);
  return stream->good();
}

bool swm_write_exact(std::ostream *stream, uint8_t *buf, size_t len) {
  if (stream == nullptr) {
    throw std::runtime_error("swm_write_exact(): \"stream\" cannot be equal to nullptr");
  }
  stream->write((const char *)buf, len);
  stream->flush();
  return stream->good();
}
