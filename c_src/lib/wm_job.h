
#pragma once

#include <vector>

#define SWM_JOB_STATE_QUEUED       "Q"
#define SWM_JOB_STATE_WAITING      "W"
#define SWM_JOB_STATE_RUNNING      "R"
#define SWM_JOB_STATE_TRANSFERRING "T"
#define SWM_JOB_STATE_FINISHED     "F"
#define SWM_JOB_STATE_ERROR        "E"
#define SWM_JOB_STATE_CANCELED     "C"


#include "wm_entity.h"
#include "wm_entity_utils.h"
#include "wm_resource.h"
#include "wm_resource.h"

namespace swm {

class SwmJob:SwmEntity {

 public:
  SwmJob();
  SwmJob(const char*, int&);

  virtual void print(const std::string &prefix, const char separator) const;

  void set_id(const std::string&);
  void set_name(const std::string&);
  void set_cluster_id(const std::string&);
  void set_nodes(const std::vector<std::string>&);
  void set_state(const std::string&);
  void set_state_details(const std::string&);
  void set_start_time(const std::string&);
  void set_submit_time(const std::string&);
  void set_end_time(const std::string&);
  void set_duration(const uint64_t&);
  void set_job_stdin(const std::string&);
  void set_job_stdout(const std::string&);
  void set_job_stderr(const std::string&);
  void set_input_files(const std::vector<std::string>&);
  void set_output_files(const std::vector<std::string>&);
  void set_workdir(const std::string&);
  void set_user_id(const std::string&);
  void set_hooks(const std::vector<std::string>&);
  void set_env(const std::vector<SwmTupleStrStr>&);
  void set_deps(const std::vector<SwmTupleAtomStr>&);
  void set_account_id(const std::string&);
  void set_gang_id(const std::string&);
  void set_execution_path(const std::string&);
  void set_script_content(const std::string&);
  void set_request(const std::vector<SwmResource>&);
  void set_resources(const std::vector<SwmResource>&);
  void set_container(const std::string&);
  void set_relocatable(const std::string&);
  void set_exitcode(const uint64_t&);
  void set_signal(const uint64_t&);
  void set_priority(const uint64_t&);
  void set_comment(const std::string&);
  void set_revision(const uint64_t&);

  std::string get_id() const;
  std::string get_name() const;
  std::string get_cluster_id() const;
  std::vector<std::string> get_nodes() const;
  std::string get_state() const;
  std::string get_state_details() const;
  std::string get_start_time() const;
  std::string get_submit_time() const;
  std::string get_end_time() const;
  uint64_t get_duration() const;
  std::string get_job_stdin() const;
  std::string get_job_stdout() const;
  std::string get_job_stderr() const;
  std::vector<std::string> get_input_files() const;
  std::vector<std::string> get_output_files() const;
  std::string get_workdir() const;
  std::string get_user_id() const;
  std::vector<std::string> get_hooks() const;
  std::vector<SwmTupleStrStr> get_env() const;
  std::vector<SwmTupleAtomStr> get_deps() const;
  std::string get_account_id() const;
  std::string get_gang_id() const;
  std::string get_execution_path() const;
  std::string get_script_content() const;
  std::vector<SwmResource> get_request() const;
  std::vector<SwmResource> get_resources() const;
  std::string get_container() const;
  std::string get_relocatable() const;
  uint64_t get_exitcode() const;
  uint64_t get_signal() const;
  uint64_t get_priority() const;
  std::string get_comment() const;
  uint64_t get_revision() const;

 private:
  std::string id;
  std::string name;
  std::string cluster_id;
  std::vector<std::string> nodes;
  std::string state;
  std::string state_details;
  std::string start_time;
  std::string submit_time;
  std::string end_time;
  uint64_t duration;
  std::string job_stdin;
  std::string job_stdout;
  std::string job_stderr;
  std::vector<std::string> input_files;
  std::vector<std::string> output_files;
  std::string workdir;
  std::string user_id;
  std::vector<std::string> hooks;
  std::vector<SwmTupleStrStr> env;
  std::vector<SwmTupleAtomStr> deps;
  std::string account_id;
  std::string gang_id;
  std::string execution_path;
  std::string script_content;
  std::vector<SwmResource> request;
  std::vector<SwmResource> resources;
  std::string container;
  std::string relocatable;
  uint64_t exitcode;
  uint64_t signal;
  uint64_t priority;
  std::string comment;
  uint64_t revision;

};

int ei_buffer_to_job(const char*, int&, std::vector<SwmJob>&);
int ei_buffer_to_job(const char*, int&, SwmJob&);

} // namespace swm
