
#include "wm_entity_utils.h"

#include <iostream>
#include <new>


using namespace swm;

template<typename T>
int resize_vector(const char* buf, const int &index, std::vector<T> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }
  if (term_type != ERL_LIST_EXT) {
      std::cerr << "Could not parse ei buffer: not an ss-tuple list" << std::endl;
      return -1;
  }
  if (term_size == 0) {
    return 0;
  }
  array.resize(term_size);
  return 0;
}

int get_term_type(const char* buf, const int &index) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }
  return term_type;
}

int get_term_size(const char* buf, const int &index) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }
  return term_size;
}

int swm::ei_buffer_to_tuple_str_str(const char* buf, int &index, SwmTupleStrStr &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT || term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a tuple" << std::endl;
    return -1;
  }
  if (ei_buffer_to_str(buf, index, tuple.x1)) {
    return -1;
  }
  if (ei_buffer_to_str(buf, index, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_str(const char* buf, int &index, SwmTupleAtomStr &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT || term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a tuple" << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, tuple.x1)) {
    return -1;
  }
  if (ei_buffer_to_str(buf, index, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_eterm(const char* buf, int &index, SwmTupleAtomEterm &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT || term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a tuple" << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, tuple.x1)) {
    return -1;
  }
  const auto term_size = get_term_size(buf, index);
  tuple.x2 = new(std::nothrow) char[term_size + 1];  // TODO: free the buffer?
  if (!tuple.x2) {
    std::cerr << "Could not allocate memory for buffer: " << (term_size + 1) << " chars" << std::endl;
    return -1;
  }
  ei_skip_term(buf, &index);
  return 0;
}


int swm::ei_buffer_to_tuple_str_str(const char* buf, int &index, std::vector<SwmTupleStrStr> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_str_str(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleStrStr at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_str(const char* buf, int &index, std::vector<SwmTupleAtomStr> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_atom_str(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleAtomStr at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_eterm(const char* buf, int &index, std::vector<SwmTupleAtomEterm> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_atom_eterm(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleAtomStr at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_uint64(const char* buf, int &index, SwmTupleAtomUint64 &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT || term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a tuple" << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, tuple.x1)) {
    return -1;
  }
  if (ei_buffer_to_uint64_t(buf, index, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_atom(const char* buf, int &index, std::string &a) {
  if (get_term_type(buf, index) != ERL_ATOM_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not an atom" << std::endl;
    return -1;
  }
  const auto term_size = get_term_size(buf, index);
  char *tmp = new(std::nothrow) char[term_size + 1];
  if (ei_decode_atom(buf, &index, tmp)) {
    std::cerr << "Could not decode atom at " << index << std::endl;
    return -1;
  }
  if (tmp == nullptr) {
    std::cerr << "Could not decode atom at " << index << ": empty pointer" << std::endl;
    return -1;
  }
  a = std::string(tmp);
  delete tmp;
  return 0;
}

int swm::ei_buffer_to_atom(const char* buf, int &index, std::vector<std::string> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &a : array) {
    if (swm::ei_buffer_to_atom(buf, index, a)) {
      std::cerr << "Could not init array of atoms at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_str(const char* buf, int &index, std::vector<std::string> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &a : array) {
    if (swm::ei_buffer_to_str(buf, index, a)) {
      std::cerr << "Could not init array of strings at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_str(const char* buf, int &index, std::string &s) {
  const auto term_size = get_term_size(buf, index);
  char *tmp = new(std::nothrow) char[term_size + 1];
  if (ei_decode_string(buf, &index, tmp)) {
    std::cerr << "Could not decode string at " << index << std::endl;
    return -1;
  }
  if (tmp == nullptr) {
    std::cerr << "Could not decode string (nullptr) at " << index << std::endl;
    return -1;
  }
  s = std::string(tmp);
  delete tmp;
  return 0;
}

int swm::ei_buffer_to_uint64_t(const char* buf, int &index, uint64_t &n) {
  const auto term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_BIG_EXT) {
    std::cerr << "Wrong eterm type " << index << ": not a ulong integer, type is " << term_type << std::endl;
    return -1;
  }
  if (ei_decode_ulong(buf, &index, &n)) {
    std::cerr << "Could not parse eterm " << index << ": not a ulong integer" << std::endl;
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_int64_t(const char* buf, int &index, int64_t &n) {
  const auto term_type = get_term_type(buf, index);
  if (term_type != ERL_INTEGER_EXT) {
    std::cerr << "Wrong eterm type " << index << ": not a long integer, type is " << term_type << std::endl;
    return -1;
  }
  if (ei_decode_long(buf, &index, &n)) {
    std::cerr << "Could not parse eterm " << index << ": not a long integer" << std::endl;
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_uint64_t(const char* buf, int &index, std::vector<uint64_t> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &a : array) {
    if (swm::ei_buffer_to_uint64_t(buf, index, a)) {
      std::cerr << "Could not init array of integers at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_int64_t(const char* buf, int &index, std::vector<int64_t> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &a : array) {
    if (swm::ei_buffer_to_int64_t(buf, index, a)) {
      std::cerr << "Could not init array of integers at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}


int swm::ei_buffer_to_double(const char* buf, int &index, double &n) {

  const auto term_type = get_term_type(buf, index);
  if (term_type != ERL_FLOAT_EXT) {
    std::cerr << "Wrong eterm type " << index << ": not a float, type is " << term_type << std::endl;
    return -1;
  }
  if (ei_decode_double(buf, &index, &n)) {
    std::cerr << "Could not parse eterm " << index << ": not a float" << std::endl;
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_double(const char* buf, int &index, std::vector<double> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &d : array) {
    if (swm::ei_buffer_to_double(buf, index, d)) {
      std::cerr << "Could not init array of floats at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

int swm::ei_buffer_to_eterm(const char* buf, int &index, char* elem) {
  // Skip for now, no point to keep a copy of binary without parsing
  if (ei_skip_term(buf, &index)) {
    std::cerr << "Could not skip eterm at pos " << index << std::endl;
    return -1;
  }
  *elem = static_cast<char>(0);
  return 0;
}

int swm::ei_buffer_to_eterm(const char* buf, int &index, std::vector<char*> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (resize_vector(buf, index, array)) {
    return -1;
  }

  for (auto &c : array) {
    if (swm::ei_buffer_to_eterm(buf, index, c)) {
      std::cerr << "Could not parse eterm list element at " << index << std::endl;
      return -1;
    }
  }
  return 0;
}

void swm::print_uint64_t(const uint64_t &x, const std::string &prefix, const char separator) {
  std::cout << prefix << x << separator;
}

void swm::print_int64_t(const int64_t &x, const std::string &prefix, const char separator) {
  std::cout << prefix << x << separator;
}

void swm::print_atom(const std::string &x, const std::string &prefix, const char separator) {
  std::cout << prefix << x << separator;
}

void swm::print_str(const std::string &x, const std::string &prefix, const char separator) {
  std::cout << prefix << x << separator;
}

void swm::print_tuple_atom_eterm(const SwmTupleAtomEterm &x, const std::string &prefix, const char separator) {
  std::cout << prefix << "{" << x.x1 << ", " << x.x2 << "}" << separator;
}

void swm::print_tuple_str_str(const SwmTupleStrStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix << "{" << x.x1 << ", " << x.x2 << "}" << separator;
}

void swm::print_tuple_atom_str(const SwmTupleAtomStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix << "{" << x.x1 << ", " << x.x2 << "}" << separator;
}
