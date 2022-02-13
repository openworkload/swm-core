
#pragma once

#include <vector>

#include "wm_entity.h"
#include "wm_entity_utils.h"

namespace swm {

class SwmQueue:SwmEntity {

 public:
  SwmQueue();
  SwmQueue(const char*);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const uint64_t&);
  void set_name(const std::string&);
  void set_state(const std::string&);
  void set_jobs(const std::vector<std::string>&);
  void set_nodes(const std::vector<std::string>&);
  void set_users(const std::vector<std::string>&);
  void set_admins(const std::vector<std::string>&);
  void set_hooks(const std::vector<std::string>&);
  void set_priority(const int64_t&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  uint64_t get_id() const;
  std::string get_name() const;
  std::string get_state() const;
  std::vector<std::string> get_jobs() const;
  std::vector<std::string> get_nodes() const;
  std::vector<std::string> get_users() const;
  std::vector<std::string> get_admins() const;
  std::vector<std::string> get_hooks() const;
  int64_t get_priority() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  uint64_t id;
  std::string name;
  std::string state;
  std::vector<std::string> jobs;
  std::vector<std::string> nodes;
  std::vector<std::string> users;
  std::vector<std::string> admins;
  std::vector<std::string> hooks;
  int64_t priority;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_queue(const char*, int, std::vector<SwmQueue>&);
int ei_buffer_to_queue(const char*, SwmQueue&);

} // namespace swm
