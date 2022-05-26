#include <iostream>

#include "wm_process.h"

#include <ei.h>


using namespace swm;


SwmProcess::SwmProcess() {
}

SwmProcess::SwmProcess(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmProcess: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmProcess header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmProcess term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->pid)) {
    std::cerr << "Could not init process::pid at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->state)) {
    std::cerr << "Could not init process::state at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->exitcode)) {
    std::cerr << "Could not init process::exitcode at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->signal)) {
    std::cerr << "Could not init process::signal at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init process::comment at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

}


void SwmProcess::set_pid(const int64_t &new_val) {
  pid = new_val;
}

void SwmProcess::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmProcess::set_exitcode(const int64_t &new_val) {
  exitcode = new_val;
}

void SwmProcess::set_signal(const int64_t &new_val) {
  signal = new_val;
}

void SwmProcess::set_comment(const std::string &new_val) {
  comment = new_val;
}

int64_t SwmProcess::get_pid() const {
  return pid;
}

std::string SwmProcess::get_state() const {
  return state;
}

int64_t SwmProcess::get_exitcode() const {
  return exitcode;
}

int64_t SwmProcess::get_signal() const {
  return signal;
}

std::string SwmProcess::get_comment() const {
  return comment;
}

int swm::ei_buffer_to_process(const char *buf, int &index, std::vector<SwmProcess> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a process list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for process at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (int i=0; i<list_size; ++i) {
    int entry_size = 0;
    int sub_term_type = 0;
    const int parsed = ei_get_type(buf, &index, &sub_term_type, &entry_size);
    if (parsed < 0) {
      std::cerr << "Could not get term type at position " << index << std::endl;
      return -1;
    }
    switch (sub_term_type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << ") is not a tuple" << std::endl;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_process(const char* buf, int &index, SwmProcess &obj) {
  obj = SwmProcess(buf, index);
  return 0;
}

void SwmProcess::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << pid << separator;
  std::cerr << prefix << state << separator;
  std::cerr << prefix << exitcode << separator;
  std::cerr << prefix << signal << separator;
  std::cerr << prefix << comment << separator;
  std::cerr << std::endl;
}

