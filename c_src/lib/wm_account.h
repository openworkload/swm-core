
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmAccount:SwmEntity {

 public:
  SwmAccount();
  SwmAccount(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_price_list(const std::string&);
  void set_users(const std::vector<std::string>&);
  void set_admins(const std::vector<std::string>&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_price_list() const;
  std::vector<std::string> get_users() const;
  std::vector<std::string> get_admins() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string price_list;
  std::vector<std::string> users;
  std::vector<std::string> admins;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_account(const char*, int&, std::vector<SwmAccount>&);
int ei_buffer_to_account(const char*, int&, SwmAccount&);

} // namespace swm
