
#pragma once

#include <erl_interface.h>

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
    ETERM* x2;
    friend std::ostream& operator<<(std::ostream& out, const SwmTupleAtomEterm &x) {
      return out << std::string("(") << x.x1 << std::string(", ETERM*)");
    }
};

class SwmTupleAtomUint64 {
  public:
    std::string x1;
    uint64_t x2;
};

int eterm_to_tuple_atom_uint64(ETERM* eterm, SwmTupleAtomUint64 &tuple);
int eterm_to_tuple_str_str(ETERM* eterm, SwmTupleStrStr &tuple);
int eterm_to_tuple_atom_str(ETERM* eterm, SwmTupleAtomStr &tuple);
int eterm_to_tuple_atom_eterm(ETERM* eterm, SwmTupleAtomEterm &tuple);
int eterm_to_tuple_str_str(ETERM* eterm, int pos, std::vector<SwmTupleStrStr> &array);
int eterm_to_tuple_atom_str(ETERM* eterm, int pos, std::vector<SwmTupleAtomStr> &array);
int eterm_to_tuple_atom_eterm(ETERM* eterm, int pos, std::vector<SwmTupleAtomEterm> &array);

int eterm_to_atom(ETERM* elem, std::string &a);
int eterm_to_atom(ETERM* term, int pos, std::string& a);
int eterm_to_atom(ETERM* term, int pos, std::vector<std::string> &array);
int eterm_to_str(ETERM* term, int pos, std::string &s);
int eterm_to_str(ETERM* term, int pos, std::vector<std::string> &array);
int eterm_to_str(ETERM* term, std::string &s);
int eterm_to_uint64_t(ETERM* term, int pos, uint64_t &x);
int eterm_to_uint64_t(ETERM* term, int pos, std::vector<uint64_t> &array);
int eterm_to_int64_t(ETERM* term, int pos, int64_t &x);
int eterm_to_int64_t(ETERM* term, int pos, std::vector<int64_t> &array);
int eterm_to_double(ETERM* term, int pos, double &x);
int eterm_to_double(ETERM* term, int pos, std::vector<double> &array);

int eterm_to_eterm(ETERM* term, int pos, ETERM* &a);
int eterm_to_eterm(ETERM* term, int pos, std::vector<ETERM*> &array);

void print_uint64_t(const uint64_t&, const std::string &prefix, const char separator);
void print_int64_t(const int64_t&, const std::string &prefix, const char separator);
void print_atom(const std::string&, const std::string &prefix, const char separator);
void print_str(const std::string&, const std::string &prefix, const char separator);
void print_tuple_atom_eterm(const SwmTupleAtomEterm&, const std::string &prefix, const char separator);
void print_tuple_str_str(const SwmTupleStrStr&, const std::string &prefix, const char separator);
void print_tuple_atom_str(const SwmTupleAtomStr&, const std::string &prefix, const char separator);

template<typename T>
int eterm_to_integer(ETERM* e, T &x);

} // namespace swm
