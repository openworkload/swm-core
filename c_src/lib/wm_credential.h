
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmCredential:SwmEntity {

 public:
  SwmCredential();
  SwmCredential(ETERM*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_remote_id(const std::string&);
  void set_tenant_name(const std::string&);
  void set_tenant_domain_name(const std::string&);
  void set_username(const std::string&);
  void set_password(const std::string&);
  void set_key_name(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_remote_id() const;
  std::string get_tenant_name() const;
  std::string get_tenant_domain_name() const;
  std::string get_username() const;
  std::string get_password() const;
  std::string get_key_name() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string remote_id;
  std::string tenant_name;
  std::string tenant_domain_name;
  std::string username;
  std::string password;
  std::string key_name;
  uint64_t revision;

};

int eterm_to_credential(ETERM*, int, std::vector<SwmCredential>&);
int eterm_to_credential(ETERM*, SwmCredential&);

} // namespace swm
