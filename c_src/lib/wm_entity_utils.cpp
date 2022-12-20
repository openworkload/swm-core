
#include "wm_entity_utils.h"

#include <iostream>
#include <new>


using namespace swm;

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

int get_term_buf_size(const char* buf, const int &index) {
  // Get buffer size with the term header
  int tmp_index = index;
  if (ei_skip_term(buf, &tmp_index)) {
    std::cerr << "Could not skip ei buffer term to get its size" << std::endl;
    return -1;
  }
  return tmp_index - index;
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
  if (term_type != ERL_SMALL_TUPLE_EXT && term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm at (index=" << index << "): not a tuple: " << term_type << std::endl;
    return -1;
  }
  int tuple_size = 0;
  if (ei_decode_tuple_header(buf, &index, &tuple_size)) {
    std::cerr << "Could not decode tuple header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return -1;
  }
  if (ei_buffer_to_str(buf, index, std::get<0>(tuple))) {
    return -1;
  }
  if (ei_buffer_to_str(buf, index, std::get<1>(tuple))) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_str(const char* buf, int &index, SwmTupleAtomStr &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT && term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm (index=" << index << "): not a tuple: " << term_type << std::endl;
    return -1;
  }
  int tuple_size = 0;
  if (ei_decode_tuple_header(buf, &index, &tuple_size)) {
    std::cerr << "Could not decode tuple header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return -1;
  }
  if (tuple_size != 2) {
    std::cerr << "Could not parse tuple which size is not 2, but " << tuple_size << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, std::get<0>(tuple))) {
    return -1;
  }
  if (ei_buffer_to_str(buf, index, std::get<1>(tuple))) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_tuple_atom_buff(const char* buf, int &index, SwmTupleAtomBuff &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT && term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm at (index=" << index << "): not a tuple: " << term_type << std::endl;
    return -1;
  }
  int tuple_size = 0;
  if (ei_decode_tuple_header(buf, &index, &tuple_size)) {
    std::cerr << "Could not decode tuple header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, std::get<0>(tuple))) {
    return -1;
  }
  auto &x = std::get<1>(tuple);
  if (ei_x_new(&x)) {
    std::cerr << "Could not create ei buffer for SwmTupleAtomBuff" << std::endl;
    return -1;
  }

  if (ei_x_append_buf(&x, &buf[index], get_term_buf_size(buf, index))) {
    std::cerr << "Could not append ei buffer for SwmTupleAtomBuff" << std::endl;
    return -1;
  }
  x.index = 0;
  ei_skip_term(buf, &index);
  return 0;
}


int swm::ei_buffer_to_tuple_str_str(const char* buf, int &index, std::vector<SwmTupleStrStr> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_str_str(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleStrStr at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_tuple_atom_str(const char* buf, int &index, std::vector<SwmTupleAtomStr> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_atom_str(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleAtomStr at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_tuple_atom_buff(const char* buf, int &index, std::vector<SwmTupleAtomBuff> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &ss : array) {
    if (swm::ei_buffer_to_tuple_atom_buff(buf, index, ss)) {
      std::cerr << "Could not init array of SwmTupleAtomStr at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_tuple_atom_uint64(const char* buf, int &index, SwmTupleAtomUint64 &tuple) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_SMALL_TUPLE_EXT && term_type != ERL_LARGE_TUPLE_EXT) {
    std::cerr << "Could not parse eterm at (index=" << index << "): not a tuple: " << term_type << std::endl;
    return -1;
  }
  int tuple_size = 0;
  if (ei_decode_tuple_header(buf, &index, &tuple_size)) {
    std::cerr << "Could not decode tuple header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return -1;
  }
  if (ei_buffer_to_atom(buf, index, std::get<0>(tuple))) {
    return -1;
  }
  if (ei_buffer_to_uint64_t(buf, index, std::get<1>(tuple))) {
    return -1;
  }
  return 0;
}

int swm::ei_buffer_to_atom(const char* buf, int &index, std::string &a) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_ATOM_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not an atom, but " << term_type << std::endl;
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
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &a : array) {
    if (swm::ei_buffer_to_atom(buf, index, a)) {
      std::cerr << "Could not init array of atoms at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_str(ei_x_buff &x, std::vector<std::string> &array) {
  return ei_buffer_to_str(x.buff, x.index, array);
}

int swm::ei_buffer_to_str(const char* buf, int &index, std::vector<std::string> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &a : array) {
    if (swm::ei_buffer_to_str(buf, index, a)) {
      std::cerr << "Could not init array of strings at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_str(ei_x_buff &x, std::string &s) {
  return ei_buffer_to_str(x.buff, x.index, s);
}

int swm::ei_buffer_to_str(const char* buf, int &index, std::string &s) {
  int term_size = 0;
  int term_type = 0;
  if (ei_get_type(buf, &index, &term_type, &term_size)) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }
  char *tmp = new(std::nothrow) char[term_size + 1];

  if (term_type == ERL_BINARY_EXT) {
    int iodata_size = 0;
    if (ei_decode_iodata(buf, &index, &iodata_size, tmp)) {
      std::cerr << "Could not decode iodata at " << index << std::endl;
      return -1;
    }
    tmp[iodata_size] = '\0';
  } else if (term_type == ERL_STRING_EXT) {
    if (ei_decode_string(buf, &index, tmp)) {
      std::cerr << "Could not decode string at " << index << std::endl;
      return -1;
    }
  } else {  // assume empty string or iodata
    ei_skip_term(buf, &index);  // last element of a list is empty list
    return 0;
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
  if (term_type != ERL_INTEGER_EXT && term_type != ERL_SMALL_INTEGER_EXT && term_type != ERL_SMALL_BIG_EXT) {
    std::cerr << "Wrong eterm type at " << index << ": not a ulong integer, type is " << term_type << std::endl;
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
  if (term_type != ERL_INTEGER_EXT && term_type != ERL_SMALL_INTEGER_EXT && term_type != ERL_SMALL_BIG_EXT) {
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
  int term_size = 0;
  int term_type = 0;
  if (ei_get_type(buf, &index, &term_type, &term_size)) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type == ERL_STRING_EXT) {  // list of integers that is incoded by erlang as string
    array.resize(term_size);
    char *tmp = new(std::nothrow) char[term_size + 1];
    if (ei_decode_string(buf, &index, tmp)) {
      std::cerr << "Could not decode string at " << index << std::endl;
      return -1;
    }
    for (int i = 0; i < term_size; ++i) {
      array[i] = tmp[i];
    }
    delete tmp;
    return 0;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list, type=" << term_type << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.resize(list_size);

  for (auto &a : array) {
    if (swm::ei_buffer_to_uint64_t(buf, index, a)) {
      std::cerr << "Could not init array of integers at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_int64_t(const char* buf, int &index, std::vector<int64_t> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &a : array) {
    if (swm::ei_buffer_to_int64_t(buf, index, a)) {
      std::cerr << "Could not init array of integers at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

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
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &d : array) {
    if (swm::ei_buffer_to_double(buf, index, d)) {
      std::cerr << "Could not init array of floats at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_map(const char* buf, int &index, std::map<std::string, std::string> &data) {
  int map_size = 0;
  if (ei_decode_map_header(buf, &index, &map_size)) {
    std::cerr << "Could not decode map at pos " << index << std::endl;
    return -1;
  }

  for (int i=0; i< map_size; ++i) {
    std::string x1;
    if (ei_buffer_to_str(buf, index, x1)) {
      return -1;
    }
    std::string x2;
    double d_tmp = 0.0;
    int64_t i_tmp = 0;
    const auto term_type = get_term_type(buf, index);
    switch (term_type) {
        case ERL_ATOM_EXT:
          if (ei_buffer_to_atom(buf, index, x2)) {
            return -1;
          }
          break;
        case ERL_FLOAT_EXT:
          if (swm::ei_buffer_to_double(buf, index, d_tmp)) {
            return -1;
          }
          x2 = std::to_string(d_tmp);
          break;
        case ERL_SMALL_INTEGER_EXT:
        case ERL_INTEGER_EXT:
        case ERL_SMALL_BIG_EXT:
        case ERL_LARGE_BIG_EXT:
          if (ei_buffer_to_int64_t(buf, index, i_tmp)) {
            return -1;
          }
          x2 = std::to_string(i_tmp);
          break;
        case ERL_LIST_EXT:
        case ERL_STRING_EXT:
          if (ei_buffer_to_str(buf, index, x2)) {
            return -1;
          }
          break;
        default:
          // unsupported or empty
          std::cerr << "Unsupported type of map value: " << term_type << std::endl;
    }
    data.emplace(std::move(x1), std::move(x2));
  }

  return 0;
}

int swm::ei_buffer_to_map(const char* buf, int &index, std::vector<std::map<std::string, std::string>> &array) {
  const int term_type = get_term_type(buf, index);
  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
    std::cerr << "Could not parse eterm " << index << ": not a list" << std::endl;
    return -1;
  }

  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size)) {
    std::cerr << "Could not decode ei list header at " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }
  array.resize(list_size);

  for (auto &c : array) {
    if (swm::ei_buffer_to_map(buf, index, c)) {
      std::cerr << "Could not parse eterm list element at " << index << std::endl;
      return -1;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

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

void swm::print_tuple_atom_buff(const SwmTupleAtomBuff &x, const std::string &prefix, const char separator) {
  std::cout << prefix << x << separator;
}

void swm::print_tuple_str_str(const SwmTupleStrStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix + "{" + std::get<0>(x) + ", " << std::get<1>(x) + "}" + separator;
}

void swm::print_tuple_atom_str(const SwmTupleAtomStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix + "{" + std::get<0>(x) + ", " << std::get<1>(x) + "}" + separator;
}

std::ostream& operator<<(std::ostream& out, const std::pair<std::string, std::string> &x) {
  out << std::string("(") << std::get<0>(x) << std::string(", ") << std::get<1>(x) << std::string(")");
  return out;
}

std::ostream& operator<<(std::ostream& out, const std::pair<std::string, ei_x_buff> &x) {
  char* term_str = nullptr;
  int index = 0;
  ei_s_print_term(&term_str, std::get<1>(x).buff, &index);
  out << std::string("(") << std::get<0>(x) << std::string(", ") + term_str + ")";
  delete[] term_str;
  return out;
}

std::ostream& operator<<(std::ostream& out, const std::pair<std::string, uint64_t> &x) {
  return out << std::string("(") + std::get<0>(x) + ", " + std::to_string(std::get<1>(x)) + ")";
}

std::ostream& operator<<(std::ostream& out, const std::map<std::string, std::string> &x) {
  out << "{";
  for (const auto &[first, second] : x) {
    out << first << ": " << second << ", ";
  }
  out << "}" << std::endl;
  return out;
}

