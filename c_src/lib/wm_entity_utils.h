
#pragma once

#include <ei.h>

#include <string>
#include <vector>

namespace swm {

// TODO consider usage of std::tuple instead of each SwmTuple* class
class SwmTupleStrStr {
  public:
    std::string x1;
    std::string x2;
    friend std::ostream& operator<<(std::ostream& out, const SwmTupleStrStr &x) {
      return out << std::string("(") << x.x1 << std::string(", ") << x.x2 << std::string(")");
    }
};

class SwmTupleAtomStr {
  public:
    std::string x1;
    std::string x2;
    friend std::ostream& operator<<(std::ostream& out, const SwmTupleAtomStr &x) {
      return out << std::string("(") << x.x1 << std::string(", ") << x.x2 << std::string(")");
    }
};

class SwmTupleAtomEterm {
  public:
    std::string x1;
    char* x2;
    friend std::ostream& operator<<(std::ostream& out, const SwmTupleAtomEterm &x) {
      return out << std::string("(") << x.x1 << std::string(", char*)");
    }
};

class SwmTupleAtomUint64 {
  public:
    std::string x1;
    uint64_t x2;
};

int ei_buffer_to_tuple_atom_uint64(const char* buf, int &index, SwmTupleAtomUint64 &tuple);
int ei_buffer_to_tuple_str_str(const char* buf, int &index, SwmTupleStrStr &tuple);
int ei_buffer_to_tuple_atom_str(const char* buf, int &index, SwmTupleAtomStr &tuple);
int ei_buffer_to_tuple_atom_eterm(const char* buf, int &index, SwmTupleAtomEterm &tuple);
int ei_buffer_to_tuple_str_str(const char* buf, int &index, std::vector<SwmTupleStrStr> &array);
int ei_buffer_to_tuple_atom_str(const char* buf, int &index, std::vector<SwmTupleAtomStr> &array);
int ei_buffer_to_tuple_atom_eterm(const char* buf, int &index, std::vector<SwmTupleAtomEterm> &array);

int ei_buffer_to_atom(const char* buf, int &index, std::string& a);
int ei_buffer_to_atom(const char* buf, int &index, std::vector<std::string> &array);
int ei_buffer_to_str(const char* buf, int &index, std::vector<std::string> &array);
int ei_buffer_to_str(const char* buf, int &index, std::string &s);
int ei_buffer_to_uint64_t(const char* buf, int &index, uint64_t &x);
int ei_buffer_to_uint64_t(const char* buf, int &index, std::vector<uint64_t> &array);
int ei_buffer_to_int64_t(const char* buf, int &index, int64_t &x);
int ei_buffer_to_int64_t(const char* buf, int &index, std::vector<int64_t> &array);
int ei_buffer_to_double(const char* buf, int &index, double &x);
int ei_buffer_to_double(const char* buf, int &index, std::vector<double> &array);

int ei_buffer_to_map(const char* buf, int &index, char* a);
int ei_buffer_to_map(const char* buf, int &index, std::vector<char*> &array);

void print_uint64_t(const uint64_t&, const std::string &prefix, const char separator);
void print_int64_t(const int64_t&, const std::string &prefix, const char separator);
void print_atom(const std::string&, const std::string &prefix, const char separator);
void print_str(const std::string&, const std::string &prefix, const char separator);
void print_tuple_atom_eterm(const SwmTupleAtomEterm&, const std::string &prefix, const char separator);
void print_tuple_str_str(const SwmTupleStrStr&, const std::string &prefix, const char separator);
void print_tuple_atom_str(const SwmTupleAtomStr&, const std::string &prefix, const char separator);

} // namespace swm
