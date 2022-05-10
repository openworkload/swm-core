
#pragma once

#include <ei.h>

#include <cstring>
#include <string>
#include <vector>

std::ostream& operator<<(std::ostream& out, const std::pair<std::string, std::string> &x);
std::ostream& operator<<(std::ostream& out, const std::pair<std::string, ei_x_buff> &x);
std::ostream& operator<<(std::ostream& out, const std::pair<std::string, uint64_t> &x);

namespace swm {

typedef std::pair<std::string, ei_x_buff> SwmTupleAtomBuff;
typedef std::pair<std::string, uint64_t> SwmTupleAtomUint64;
typedef std::pair<std::string, std::string> SwmTupleStrStr;
typedef std::pair<std::string, std::string> SwmTupleAtomStr;

int ei_buffer_to_tuple_atom_uint64(const char* buf, int &index, SwmTupleAtomUint64 &tuple);
int ei_buffer_to_tuple_str_str(const char* buf, int &index, SwmTupleStrStr &tuple);
int ei_buffer_to_tuple_atom_str(const char* buf, int &index, SwmTupleAtomStr &tuple);
int ei_buffer_to_tuple_atom_buff(const char* buf, int &index, SwmTupleAtomBuff &tuple);
int ei_buffer_to_tuple_str_str(const char* buf, int &index, std::vector<SwmTupleStrStr> &array);
int ei_buffer_to_tuple_atom_str(const char* buf, int &index, std::vector<SwmTupleAtomStr> &array);
int ei_buffer_to_tuple_atom_buff(const char* buf, int &index, std::vector<SwmTupleAtomBuff> &array);

int ei_buffer_to_atom(const char* buf, int &index, std::string& a);
int ei_buffer_to_atom(const char* buf, int &index, std::vector<std::string> &array);
int ei_buffer_to_str(ei_x_buff &x, std::vector<std::string> &array);
int ei_buffer_to_str(ei_x_buff &x, std::string &s);
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
void print_tuple_atom_buff(const SwmTupleAtomBuff &, const std::string &prefix, const char separator);
void print_tuple_str_str(const SwmTupleStrStr&, const std::string &prefix, const char separator);
void print_tuple_atom_str(const SwmTupleAtomStr&, const std::string &prefix, const char separator);

} // namespace swm
