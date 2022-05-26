#ifndef WM_IO_H
#define WM_IO_H

#include <ei.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <iostream>

#define SWM_LOG_LEVEL_INFO   0
#define SWM_LOG_LEVEL_DEBUG1 1
#define SWM_LOG_LEVEL_DEBUG2 2

#define ERLANG_BINARY_FORMAT_VERSION 131

void swm_log_init(int level, FILE *stream);
int swm_get_log_level();
void swm_loge(const char* message, ...);
void swm_logi(const char* message, ...);
void swm_logd(const char* message, ...);
void swm_logdd(const char* message, ...);

bool swm_read_length(std::istream *stream, uint32_t *len);
bool swm_read_exact(std::istream *stream, char *buf, size_t len);
bool swm_write_exact(std::ostream *stream, char *buf, size_t len);

void print_ei_buf(const char* buf, int index);

#endif
