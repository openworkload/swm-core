#include "wm_entity_utils.h"

#include <iostream>

#include "wm_process.h"

#include <ei.h>


using namespace swm;


SwmProcess::SwmProcess() {
}

SwmProcess::SwmProcess(const char* buf) {
  if (!buf) {
    std::cerr << "Cannot convert ei buffer into SwmProcess: empty" << std::endl;
    return;
  }

  int term_size = 0;
  int index = 0;

  if (ei_decode_tuple_header(buf, &index, &term_size) < 0) {
    std::cerr << "Cannot decode SwmProcess header from ei buffer" << std::endl;
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->pid)) {
    std::cerr << "Could not initialize process property at position=2" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->state)) {
    std::cerr << "Could not initialize process property at position=3" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->exitcode)) {
    std::cerr << "Could not initialize process property at position=4" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_int64_t(buf, index, this->signal)) {
    std::cerr << "Could not initialize process property at position=5" << std::endl;
    ei_print_term(stderr, buf, index);
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not initialize process property at position=6" << std::endl;
    ei_print_term(stderr, buf, index);
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


int swm::ei_buffer_to_process(const char* buf, const int pos, std::vector<SwmProcess> &array) {
  int term_size = 0
  int term_type = 0;
  const int parsed = ei_get_type(buf, index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << pos << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse term: not a process list at position " << pos << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &pos, &list_size) < 0) {
    std::cerr << "Could not parse list for process at position " << pos << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.reserve(list_size);
  for (size_t i=0; i<list_size; ++i) {
    ei_term term;
    if (ei_decode_ei_term(buf, pos, &term) < 0) {
      std::cerr << "Could not decode list element at position " << pos << std::endl;
      return -1;
    }
    array.push_back(SwmProcess(term));
  }
  return 0;
}


int swm::eterm_to_process(char* buf, SwmProcess &obj) {
  ei_term term;
  if (ei_decode_ei_term(buf, 0, &term) < 0) {
    std::cerr << "Could not decode element for " << process << std::endl;
    return -1;
  }
  obj = SwmProcess(eterm);
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


