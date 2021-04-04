
#include "wm_entity_utils.h"

#include <erl_interface.h>
#include <ei.h>

#include <iostream>


using namespace swm;


template<typename T>
int resize_vector(ETERM* elist, std::vector<T> &array) {
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not an ss-tuple list" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.resize(sz);
  return 0;
}

int swm::eterm_to_tuple_str_str(ETERM* eterm, SwmTupleStrStr &tuple) {
  if (!ERL_IS_TUPLE(eterm)) {
    std::cerr << "Could not parse eterm: not a tuple" << std::endl;
    return -1;
  }
  if (eterm_to_str(eterm, 1, tuple.x1)) {
    return -1;
  }
  if (eterm_to_str(eterm, 2, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::eterm_to_tuple_atom_str(ETERM* eterm, SwmTupleAtomStr &tuple) {
  if (!ERL_IS_TUPLE(eterm)) {
    std::cerr << "Could not parse eterm: not a tuple" << std::endl;
    return -1;
  }
  if (eterm_to_atom(eterm, 1, tuple.x1)) {
    return -1;
  }
  if (eterm_to_str(eterm, 2, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::eterm_to_tuple_atom_eterm(ETERM* eterm, SwmTupleAtomEterm &tuple) {
  if (!ERL_IS_TUPLE(eterm)) {
    std::cerr << "Could not parse eterm: not a tuple" << std::endl;
    return -1;
  }
  if (eterm_to_atom(eterm, 1, tuple.x1)) {
    return -1;
  }
  // TODO free the copy of the term
  tuple.x2 = erl_copy_term(erl_element(2, eterm));
  if (!tuple.x2) {
    return -1;
  }
  return 0;
}

int swm::eterm_to_tuple_str_str(ETERM* eterm, int pos, std::vector<SwmTupleStrStr> &array) {
  ETERM* elist = erl_element(pos, eterm);
  if (!elist) {
    return -1;
  }
  if (resize_vector(elist, array)) {
    return -1;
  }
  for (auto &ss : array) {
    ETERM* x = erl_hd(elist);
    if (!x) {
      continue;
    }
    if (swm::eterm_to_tuple_str_str(x, ss)) {
      std::cerr << "Could not init array of SwmTupleStrStr" << std::endl;
      return -1;
    }
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_tuple_atom_str(ETERM* eterm, int pos, std::vector<SwmTupleAtomStr> &array) {
  ETERM* elist = erl_element(pos, eterm);
  if (!elist) {
    return -1;
  }
  if (resize_vector(elist, array)) {
    return -1;
  }
  for (auto &as : array) {
    ETERM* x = erl_hd(elist);
    if (!x) {
      continue;
    }
    if (swm::eterm_to_tuple_atom_str(x, as)) {
      std::cerr << "Could not init array of SwmTupleAtomStr" << std::endl;
      return -1;
    }
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_tuple_atom_eterm(ETERM* eterm, int pos, std::vector<SwmTupleAtomEterm> &array) {
  ETERM* elist = erl_element(pos, eterm);
  if (!elist) {
    return -1;
  }
  if (resize_vector(elist, array)) {
    return -1;
  }
  for (auto &ae : array) {
    ETERM* x = erl_hd(elist);
    if (!x) {
      continue;
    }
    if (swm::eterm_to_tuple_atom_eterm(x, ae)) {
      std::cerr << "Could not init array of SwmTupleAtomEterm" << std::endl;
      return -1;
    }
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_tuple_atom_uint64(ETERM* eterm, SwmTupleAtomUint64 &tuple) {
  if (!ERL_IS_TUPLE(eterm)) {
    std::cerr << "Could not parse eterm: not a tuple" << std::endl;
    return -1;
  }
  if (eterm_to_atom(eterm, 1, tuple.x1)) {
    return -1;
  }
  ETERM* elem = erl_element(2, eterm);
  if (eterm_to_integer(elem, tuple.x2)) {
    return -1;
  }
  return 0;
}

int swm::eterm_to_atom(ETERM* e, std::string &a) {
  if (!e) {
    return -1;
  }
  if (!ERL_IS_ATOM(e)) {
    std::cerr << "Could not parse eterm: not an atom" << std::endl;
    return -1;
  }
  char *tmp = ERL_ATOM_PTR(e);
  if (tmp == nullptr) {
    return -1;
  }
  a = std::string(tmp);
  return 0;
}

int swm::eterm_to_atom(ETERM* term, int pos, std::string &a) {
  ETERM* elem = erl_element(pos, term);
  return eterm_to_atom(elem, a);
}

int swm::eterm_to_atom(ETERM* term, int pos, std::vector<std::string> &array) {
  ETERM* elist = erl_element(pos, term);
  if (!elist) {
    return -1;
  }
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not an atom array" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.resize(sz);

  for (auto &str : array) {
    ETERM* x = erl_hd(elist);
    if (!x) {
      continue;
    }
    if (!ERL_IS_ATOM(x)) {
      std::cerr << "Could not parse eterm: not an atom" << std::endl;
      return -1;
    }
    str = ERL_ATOM_PTR(x);
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_str(ETERM* term, int pos, std::vector<std::string> &array) {
  ETERM* elist = erl_element(pos, term);
  if (!elist) {
    return -1;
  }
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a str array" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.resize(sz);

  for (auto &str : array) {
    ETERM* x = erl_hd(elist);
    if (!x) {
      continue;
    }
    if (!ERL_IS_LIST(x)) {
      std::cerr << "Could not parse eterm: not a string: ";
      erl_print_term(stderr, x);
      std::cerr << std::endl;
      return -1;
    }
    str = erl_iolist_to_string(x);
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_str(ETERM* term, int pos, std::string &s) {
  ETERM* elem = erl_element(pos, term);
  if (!elem) {
    return -1;
  }
  return eterm_to_str(elem, s);
}

int swm::eterm_to_str(ETERM* term, std::string &s) {
  if (!ERL_IS_LIST(term) && !ERL_IS_BINARY(term)) {
    std::cerr << "Could not parse eterm: not a string: ";
    erl_print_term(stderr, term);
    std::cerr << std::endl;
    return -1;
  }
  char *tmp = erl_iolist_to_string(erl_iolist_to_binary(term));
  if (tmp == nullptr) {
    return -1;
  }
  s = std::string(tmp);
  return 0;
}

template<typename T>
int swm::eterm_to_integer(ETERM* e, T &x) {
  if (ERL_IS_INTEGER(e)) {
    x = ERL_INT_VALUE(e);
  }
  else if (ERL_IS_UNSIGNED_INTEGER(e)) {
    x = ERL_INT_UVALUE(e);
  }
  else if (ERL_IS_LONGLONG(e)) {
    x = ERL_LL_VALUE(e);
  }
  else if (ERL_IS_UNSIGNED_LONGLONG(e)) {
    x = ERL_LL_UVALUE(e);
  }
  else {
    std::cerr << "Could not parse eterm: not an integer: ";
    erl_print_term(stderr, e);
    std::cerr << std::endl;
    return -1;
  }
  return 0;
}

int swm::eterm_to_uint64_t(ETERM* term, int pos, uint64_t &x) {
  ETERM* elem = erl_element(pos, term);
  if (!elem) {
    return -1;
  }
  return eterm_to_integer(elem, x);
}

int swm::eterm_to_uint64_t(ETERM* term, int pos, std::vector<uint64_t> &array) {
  ETERM* elist = erl_element(pos, term);
  if (!elist) {
    return -1;
  }
  if (resize_vector(elist, array)) {
    return -1;
  }
  for (auto &n : array) {
    ETERM* e = erl_hd(elist);
    if (!e) {
      continue;
    }
    if (eterm_to_integer(e, n)) {
      return -1;
    }
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_int64_t(ETERM* term, int pos, int64_t &n) {
  ETERM* elem = erl_element(pos, term);
  if (!elem) {
    return -1;
  }
  return eterm_to_integer(elem, n);
}

int swm::eterm_to_int64_t(ETERM* term, int pos, std::vector<int64_t> &array) {
  ETERM* elist = erl_element(pos, term);
  if (!elist) {
    return -1;
  }
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a ulong array" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }

  for (auto &n : array) {
    ETERM* e = erl_hd(elist);
    if (!e) {
      continue;
    }
    if (eterm_to_integer(e, n)) {
      return -1;
    }
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_double(ETERM* term, int pos, double &n) {
  ETERM* elem = erl_element(pos, term);
  if (!elem) {
    return -1;
  }
  if (!ERL_IS_FLOAT(elem)) {
    return -1;
  }
  n = ERL_FLOAT_VALUE(elem);
  return 0;
}

int swm::eterm_to_double(ETERM* term, int pos, std::vector<double> &array) {
  ETERM* elist = erl_element(pos, term);
  if (!elist) {
    return -1;
  }
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a ulong array" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }

  for (auto &n : array) {
    ETERM* e = erl_hd(elist);
    if (!e) {
      continue;
    }
    if (!ERL_IS_FLOAT(e)) {
      return -1;
    }
    n = ERL_FLOAT_VALUE(e);
    elist = erl_tl(elist);
  }
  return 0;
}

int swm::eterm_to_eterm(ETERM* term, int pos, ETERM* &elem) {
  // TODO free the copy of the term
  elem = erl_copy_term(erl_element(pos, term));
  if (!elem) {
    std::cerr << "Could not parse eterm at pos " << pos << std::endl;
    return -1;
  }
  return 0;
}

int swm::eterm_to_eterm(ETERM* term, int pos, std::vector<ETERM*> &array) {
  // TODO free the copy of the term list
  ETERM *elist = erl_copy_term(erl_element(pos, term));
  if (!elist) {
    return -1;
  }
  if (!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not an ETERM array" << std::endl;
    return -1;
  }
  if (ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  for (auto &e : array) {
    e = erl_hd(elist);
    elist = erl_tl(elist);
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
  std::cout << prefix << "{" << x.x1 << ", ";
  erl_print_term(stdout, x.x2);
  std::cout << "}" << separator;
}

void swm::print_tuple_str_str(const SwmTupleStrStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix << "{" << x.x1 << ", " << x.x2 << "}" << separator;
}

void swm::print_tuple_atom_str(const SwmTupleAtomStr &x, const std::string &prefix, const char separator) {
  std::cout << prefix << "{" << x.x1 << ", " << x.x2 << "}" << separator;
}
