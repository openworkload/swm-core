#include "wm_entity.h"
#include "wm_io.h"

#include <cstring>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define LOG_OUT_STREAM stderr

static int g_log_level = SWM_LOG_LEVEL_INFO;
static FILE *g_log_stream = NULL;

void _print_log_format(const char* tag, const char* message, va_list args, const bool end_line) {
  time_t now;
  time(&now);
  char *date = ctime(&now);
  date[strlen(date) - 1] = '\0';
  fprintf(LOG_OUT_STREAM, "%s [%s] ", date, tag);
  vfprintf(LOG_OUT_STREAM, message, args);
  if (end_line) {
    fprintf(LOG_OUT_STREAM, "\n");
  }
}

void swm_log_init(int level, FILE *stream) {
  g_log_level = level;
  g_log_stream = stream;
}

int swm_get_log_level() {
  return g_log_level;
}

void swm_logi(const char* message, ...) {
  va_list args;
  va_start(args, message);
  if (message == NULL) {
    fprintf(LOG_OUT_STREAM, "\n");
  } else {
    _print_log_format("INFO", message, args, true);
  }
  va_end(args);
  fflush(LOG_OUT_STREAM);
}

void swm_loge(const char* message, ...) {
  va_list args;
  va_start(args, message);
  if (message == NULL) {
    fprintf(LOG_OUT_STREAM, "\n");
  } else {
    _print_log_format("ERROR", message, args, true);
  }
  va_end(args);
  fflush(LOG_OUT_STREAM);
}

void swm_logd(const char* message, ...) {
  if (g_log_level < SWM_LOG_LEVEL_DEBUG1) {
    return;
  }
  va_list args;
  va_start(args, message);
  if (message == NULL) {
    fprintf(LOG_OUT_STREAM, "\n");
  } else {
    _print_log_format("DEBUG", message, args, true);
  }
  va_end(args);
  fflush(LOG_OUT_STREAM);
}

void swm_logdd(const char* message, ...) {
  if (g_log_level < SWM_LOG_LEVEL_DEBUG2) {
    return;
  }
  va_list args;
  va_start(args, message);
  _print_log_format("DEBUG2", message, args, true);
  va_end(args);
  fflush(LOG_OUT_STREAM);
}

bool swm_read_length(std::istream *stream, uint32_t *len) {
  // swm_read_exact() checks stream for nullptr
  unsigned char buf[4];
  if (!swm_read_exact(stream, (char*)buf, 4)) {
    return false;
  }

  // Convert 4 bytes to unsigned long:
  *len = (buf[0] << 24) |
         (buf[1] << 16) |
         (buf[2] << 8)  |
          buf[3];
  return true;
}

bool swm_read_exact(std::istream *stream, char *buf, size_t len) {
  if (stream == nullptr) {
    throw std::runtime_error("swm_read_exact(): \"stream\" cannot be equal to nullptr");
  }

  stream->read(buf, len);
  return stream->good();
}

bool swm_write_exact(std::ostream *stream, char *buf, size_t len) {
  if (stream == nullptr) {
    throw std::runtime_error("swm_write_exact(): \"stream\" cannot be equal to nullptr");
  }
  stream->write(buf, len);
  stream->flush();
  return stream->good();
}
