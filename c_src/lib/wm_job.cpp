

#include "wm_entity_utils.h"

#include <iostream>

#include "wm_job.h"

#include <erl_interface.h>
#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmJob::SwmJob() {
}

SwmJob::SwmJob(ETERM *term) {
  if(!term) {
    std::cerr << "Cannot convert ETERM to SwmJob: empty" << std::endl;
    return;
  }
  if(eterm_to_str(term, 2, id)) {
    std::cerr << "Could not initialize job paremeter at position 2" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 3, name)) {
    std::cerr << "Could not initialize job paremeter at position 3" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 4, cluster_id)) {
    std::cerr << "Could not initialize job paremeter at position 4" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 5, nodes)) {
    std::cerr << "Could not initialize job paremeter at position 5" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 6, state)) {
    std::cerr << "Could not initialize job paremeter at position 6" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 7, start_time)) {
    std::cerr << "Could not initialize job paremeter at position 7" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 8, submit_time)) {
    std::cerr << "Could not initialize job paremeter at position 8" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 9, end_time)) {
    std::cerr << "Could not initialize job paremeter at position 9" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 10, duration)) {
    std::cerr << "Could not initialize job paremeter at position 10" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 11, job_stdin)) {
    std::cerr << "Could not initialize job paremeter at position 11" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 12, job_stdout)) {
    std::cerr << "Could not initialize job paremeter at position 12" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 13, job_stderr)) {
    std::cerr << "Could not initialize job paremeter at position 13" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 14, input_files)) {
    std::cerr << "Could not initialize job paremeter at position 14" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 15, output_files)) {
    std::cerr << "Could not initialize job paremeter at position 15" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 16, workdir)) {
    std::cerr << "Could not initialize job paremeter at position 16" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 17, user_id)) {
    std::cerr << "Could not initialize job paremeter at position 17" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 18, hooks)) {
    std::cerr << "Could not initialize job paremeter at position 18" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_str_str(term, 19, env)) {
    std::cerr << "Could not initialize job paremeter at position 19" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_tuple_atom_str(term, 20, deps)) {
    std::cerr << "Could not initialize job paremeter at position 20" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 21, projects)) {
    std::cerr << "Could not initialize job paremeter at position 21" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 22, account_id)) {
    std::cerr << "Could not initialize job paremeter at position 22" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 23, gang_id)) {
    std::cerr << "Could not initialize job paremeter at position 23" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 24, execution_path)) {
    std::cerr << "Could not initialize job paremeter at position 24" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 25, script_content)) {
    std::cerr << "Could not initialize job paremeter at position 25" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 26, request)) {
    std::cerr << "Could not initialize job paremeter at position 26" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_resource(term, 27, resources)) {
    std::cerr << "Could not initialize job paremeter at position 27" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 28, container)) {
    std::cerr << "Could not initialize job paremeter at position 28" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_atom(term, 29, relocatable)) {
    std::cerr << "Could not initialize job paremeter at position 29" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 30, exitcode)) {
    std::cerr << "Could not initialize job paremeter at position 30" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 31, signal)) {
    std::cerr << "Could not initialize job paremeter at position 31" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 32, priority)) {
    std::cerr << "Could not initialize job paremeter at position 32" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_str(term, 33, comment)) {
    std::cerr << "Could not initialize job paremeter at position 33" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
  if(eterm_to_uint64_t(term, 34, revision)) {
    std::cerr << "Could not initialize job paremeter at position 34" << std::endl;
    erl_print_term(stderr, term);
    return;
  }
}



void SwmJob::set_id(const std::string &new_val) {
  id = new_val;
}

void SwmJob::set_name(const std::string &new_val) {
  name = new_val;
}

void SwmJob::set_cluster_id(const std::string &new_val) {
  cluster_id = new_val;
}

void SwmJob::set_nodes(const std::vector<std::string> &new_val) {
  nodes = new_val;
}

void SwmJob::set_state(const std::string &new_val) {
  state = new_val;
}

void SwmJob::set_start_time(const std::string &new_val) {
  start_time = new_val;
}

void SwmJob::set_submit_time(const std::string &new_val) {
  submit_time = new_val;
}

void SwmJob::set_end_time(const std::string &new_val) {
  end_time = new_val;
}

void SwmJob::set_duration(const uint64_t &new_val) {
  duration = new_val;
}

void SwmJob::set_job_stdin(const std::string &new_val) {
  job_stdin = new_val;
}

void SwmJob::set_job_stdout(const std::string &new_val) {
  job_stdout = new_val;
}

void SwmJob::set_job_stderr(const std::string &new_val) {
  job_stderr = new_val;
}

void SwmJob::set_input_files(const std::vector<std::string> &new_val) {
  input_files = new_val;
}

void SwmJob::set_output_files(const std::vector<std::string> &new_val) {
  output_files = new_val;
}

void SwmJob::set_workdir(const std::string &new_val) {
  workdir = new_val;
}

void SwmJob::set_user_id(const std::string &new_val) {
  user_id = new_val;
}

void SwmJob::set_hooks(const std::vector<std::string> &new_val) {
  hooks = new_val;
}

void SwmJob::set_env(const std::vector<SwmTupleStrStr> &new_val) {
  env = new_val;
}

void SwmJob::set_deps(const std::vector<SwmTupleAtomStr> &new_val) {
  deps = new_val;
}

void SwmJob::set_projects(const std::vector<uint64_t> &new_val) {
  projects = new_val;
}

void SwmJob::set_account_id(const std::string &new_val) {
  account_id = new_val;
}

void SwmJob::set_gang_id(const std::string &new_val) {
  gang_id = new_val;
}

void SwmJob::set_execution_path(const std::string &new_val) {
  execution_path = new_val;
}

void SwmJob::set_script_content(const std::string &new_val) {
  script_content = new_val;
}

void SwmJob::set_request(const std::vector<SwmResource> &new_val) {
  request = new_val;
}

void SwmJob::set_resources(const std::vector<SwmResource> &new_val) {
  resources = new_val;
}

void SwmJob::set_container(const std::string &new_val) {
  container = new_val;
}

void SwmJob::set_relocatable(const std::string &new_val) {
  relocatable = new_val;
}

void SwmJob::set_exitcode(const uint64_t &new_val) {
  exitcode = new_val;
}

void SwmJob::set_signal(const uint64_t &new_val) {
  signal = new_val;
}

void SwmJob::set_priority(const uint64_t &new_val) {
  priority = new_val;
}

void SwmJob::set_comment(const std::string &new_val) {
  comment = new_val;
}

void SwmJob::set_revision(const uint64_t &new_val) {
  revision = new_val;
}

std::string SwmJob::get_id() const {
  return id;
}

std::string SwmJob::get_name() const {
  return name;
}

std::string SwmJob::get_cluster_id() const {
  return cluster_id;
}

std::vector<std::string> SwmJob::get_nodes() const {
  return nodes;
}

std::string SwmJob::get_state() const {
  return state;
}

std::string SwmJob::get_start_time() const {
  return start_time;
}

std::string SwmJob::get_submit_time() const {
  return submit_time;
}

std::string SwmJob::get_end_time() const {
  return end_time;
}

uint64_t SwmJob::get_duration() const {
  return duration;
}

std::string SwmJob::get_job_stdin() const {
  return job_stdin;
}

std::string SwmJob::get_job_stdout() const {
  return job_stdout;
}

std::string SwmJob::get_job_stderr() const {
  return job_stderr;
}

std::vector<std::string> SwmJob::get_input_files() const {
  return input_files;
}

std::vector<std::string> SwmJob::get_output_files() const {
  return output_files;
}

std::string SwmJob::get_workdir() const {
  return workdir;
}

std::string SwmJob::get_user_id() const {
  return user_id;
}

std::vector<std::string> SwmJob::get_hooks() const {
  return hooks;
}

std::vector<SwmTupleStrStr> SwmJob::get_env() const {
  return env;
}

std::vector<SwmTupleAtomStr> SwmJob::get_deps() const {
  return deps;
}

std::vector<uint64_t> SwmJob::get_projects() const {
  return projects;
}

std::string SwmJob::get_account_id() const {
  return account_id;
}

std::string SwmJob::get_gang_id() const {
  return gang_id;
}

std::string SwmJob::get_execution_path() const {
  return execution_path;
}

std::string SwmJob::get_script_content() const {
  return script_content;
}

std::vector<SwmResource> SwmJob::get_request() const {
  return request;
}

std::vector<SwmResource> SwmJob::get_resources() const {
  return resources;
}

std::string SwmJob::get_container() const {
  return container;
}

std::string SwmJob::get_relocatable() const {
  return relocatable;
}

uint64_t SwmJob::get_exitcode() const {
  return exitcode;
}

uint64_t SwmJob::get_signal() const {
  return signal;
}

uint64_t SwmJob::get_priority() const {
  return priority;
}

std::string SwmJob::get_comment() const {
  return comment;
}

uint64_t SwmJob::get_revision() const {
  return revision;
}


int swm::eterm_to_job(ETERM* term, int pos, std::vector<SwmJob> &array) {
  ETERM* elist = erl_element(pos, term);
  if(!ERL_IS_LIST(elist)) {
    std::cerr << "Could not parse eterm: not a job list" << std::endl;
    return -1;
  }
  if(ERL_IS_EMPTY_LIST(elist)) {
    return 0;
  }
  const size_t sz = erl_length(elist);
  array.reserve(sz);
  for(size_t i=0; i<sz; ++i) {
    ETERM* e = erl_hd(elist);
    array.push_back(SwmJob(e));
    elist = erl_tl(elist);
  }
  return 0;
}


int swm::eterm_to_job(ETERM* eterm, SwmJob &obj) {
  obj = SwmJob(eterm);
  return 0;
}


void SwmJob::print(const std::string &prefix, const char separator) const {
    std::cerr << prefix << id << separator;
    std::cerr << prefix << name << separator;
    std::cerr << prefix << cluster_id << separator;
  if(nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for(const auto &q: nodes) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << state << separator;
    std::cerr << prefix << start_time << separator;
    std::cerr << prefix << submit_time << separator;
    std::cerr << prefix << end_time << separator;
    std::cerr << prefix << duration << separator;
    std::cerr << prefix << job_stdin << separator;
    std::cerr << prefix << job_stdout << separator;
    std::cerr << prefix << job_stderr << separator;
  if(input_files.empty()) {
    std::cerr << prefix << "input_files: []" << separator;
  } else {
    std::cerr << prefix << "input_files" << ": [";
    for(const auto &q: input_files) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(output_files.empty()) {
    std::cerr << prefix << "output_files: []" << separator;
  } else {
    std::cerr << prefix << "output_files" << ": [";
    for(const auto &q: output_files) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << workdir << separator;
    std::cerr << prefix << user_id << separator;
  if(hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for(const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(env.empty()) {
    std::cerr << prefix << "env: []" << separator;
  } else {
    std::cerr << prefix << "env" << ": [";
    for(const auto &q: env) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(deps.empty()) {
    std::cerr << prefix << "deps: []" << separator;
  } else {
    std::cerr << prefix << "deps" << ": [";
    for(const auto &q: deps) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if(projects.empty()) {
    std::cerr << prefix << "projects: []" << separator;
  } else {
    std::cerr << prefix << "projects" << ": [";
    for(const auto &q: projects) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << account_id << separator;
    std::cerr << prefix << gang_id << separator;
    std::cerr << prefix << execution_path << separator;
    std::cerr << prefix << script_content << separator;
  if(request.empty()) {
    std::cerr << prefix << "request: []" << separator;
  } else {
    std::cerr << prefix << "request" << ": [";
    for(const auto &q: request) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  if(resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for(const auto &q: resources) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
    std::cerr << prefix << container << separator;
    std::cerr << prefix << relocatable << separator;
    std::cerr << prefix << exitcode << separator;
    std::cerr << prefix << signal << separator;
    std::cerr << prefix << priority << separator;
    std::cerr << prefix << comment << separator;
    std::cerr << prefix << revision << separator;
  std::cerr << std::endl;
}


