#include <iostream>

#include "wm_job.h"

#include <ei.h>

#include "wm_resource.h"

using namespace swm;


SwmJob::SwmJob() {
}

SwmJob::SwmJob(const char* buf, int &index) {
  if (!buf) {
    std::cerr << "Could not convert ei buffer into SwmJob: null" << std::endl;
    return;
  }

  int term_size = 0;
  if (ei_decode_tuple_header(buf, &index, &term_size)) {
    std::cerr << "Could not decode SwmJob header from ei buffer: ";
    ei_print_term(stdout, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_skip_term(buf, &index) < 0) {  // first atom is the term name
    std::cerr << "Could not skip SwmJob term first atom: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->id)) {
    std::cerr << "Could not init job::id at pos 2: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->name)) {
    std::cerr << "Could not init job::name at pos 3: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->cluster_id)) {
    std::cerr << "Could not init job::cluster_id at pos 4: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->nodes)) {
    std::cerr << "Could not init job::nodes at pos 5: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->state)) {
    std::cerr << "Could not init job::state at pos 6: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->start_time)) {
    std::cerr << "Could not init job::start_time at pos 7: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->submit_time)) {
    std::cerr << "Could not init job::submit_time at pos 8: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->end_time)) {
    std::cerr << "Could not init job::end_time at pos 9: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->duration)) {
    std::cerr << "Could not init job::duration at pos 10: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_stdin)) {
    std::cerr << "Could not init job::job_stdin at pos 11: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_stdout)) {
    std::cerr << "Could not init job::job_stdout at pos 12: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->job_stderr)) {
    std::cerr << "Could not init job::job_stderr at pos 13: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->input_files)) {
    std::cerr << "Could not init job::input_files at pos 14: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->output_files)) {
    std::cerr << "Could not init job::output_files at pos 15: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->workdir)) {
    std::cerr << "Could not init job::workdir at pos 16: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->user_id)) {
    std::cerr << "Could not init job::user_id at pos 17: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->hooks)) {
    std::cerr << "Could not init job::hooks at pos 18: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_tuple_str_str(buf, index, this->env)) {
    std::cerr << "Could not init job::env at pos 19: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_tuple_atom_str(buf, index, this->deps)) {
    std::cerr << "Could not init job::deps at pos 20: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->projects)) {
    std::cerr << "Could not init job::projects at pos 21: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->account_id)) {
    std::cerr << "Could not init job::account_id at pos 22: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->gang_id)) {
    std::cerr << "Could not init job::gang_id at pos 23: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->execution_path)) {
    std::cerr << "Could not init job::execution_path at pos 24: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->script_content)) {
    std::cerr << "Could not init job::script_content at pos 25: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->request)) {
    std::cerr << "Could not init job::request at pos 26: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_resource(buf, index, this->resources)) {
    std::cerr << "Could not init job::resources at pos 27: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->container)) {
    std::cerr << "Could not init job::container at pos 28: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_atom(buf, index, this->relocatable)) {
    std::cerr << "Could not init job::relocatable at pos 29: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->exitcode)) {
    std::cerr << "Could not init job::exitcode at pos 30: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->signal)) {
    std::cerr << "Could not init job::signal at pos 31: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->priority)) {
    std::cerr << "Could not init job::priority at pos 32: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_str(buf, index, this->comment)) {
    std::cerr << "Could not init job::comment at pos 33: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
    return;
  }

  if (ei_buffer_to_uint64_t(buf, index, this->revision)) {
    std::cerr << "Could not init job::revision at pos 34: ";
    ei_print_term(stderr, buf, &index);
    std::cerr << std::endl;
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

int swm::ei_buffer_to_job(const char *buf, int &index, std::vector<SwmJob> &array) {
  int term_size = 0;
  int term_type = 0;
  const int parsed = ei_get_type(buf, &index, &term_type, &term_size);
  if (parsed < 0) {
    std::cerr << "Could not get term type at position " << index << std::endl;
    return -1;
  }

  if (term_type != ERL_LIST_EXT && term_type != ERL_NIL_EXT) {
      std::cerr << "Could not parse term: not a job list at " << index << ": " << term_type << std::endl;
      return -1;
  }
  int list_size = 0;
  if (ei_decode_list_header(buf, &index, &list_size) < 0) {
    std::cerr << "Could not parse list for job at position " << index << std::endl;
    return -1;
  }
  if (list_size == 0) {
    return 0;
  }

  array.reserve(list_size);
  for (int i=0; i<list_size; ++i) {
    int entry_size = 0;
    int sub_term_type = 0;
    const int parsed = ei_get_type(buf, &index, &sub_term_type, &entry_size);
    if (parsed < 0) {
      std::cerr << "Could not get term type at position " << index << std::endl;
      return -1;
    }
    switch (sub_term_type) {
      case ERL_SMALL_TUPLE_EXT:
      case ERL_LARGE_TUPLE_EXT:
        array.emplace_back(buf, index);
        break;
      default:
        std::cerr << "List element (at position " << i << ") is not a tuple" << std::endl;
    }
  }
  ei_skip_term(buf, &index);  // last element of a list is empty list

  return 0;
}

int swm::ei_buffer_to_job(const char* buf, int &index, SwmJob &obj) {
  obj = SwmJob(buf, index);
  return 0;
}

void SwmJob::print(const std::string &prefix, const char separator) const {
  std::cerr << prefix << id << separator;
  std::cerr << prefix << name << separator;
  std::cerr << prefix << cluster_id << separator;
  if (nodes.empty()) {
    std::cerr << prefix << "nodes: []" << separator;
  } else {
    std::cerr << prefix << "nodes" << ": [";
    for (const auto &q: nodes) {
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
  if (input_files.empty()) {
    std::cerr << prefix << "input_files: []" << separator;
  } else {
    std::cerr << prefix << "input_files" << ": [";
    for (const auto &q: input_files) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (output_files.empty()) {
    std::cerr << prefix << "output_files: []" << separator;
  } else {
    std::cerr << prefix << "output_files" << ": [";
    for (const auto &q: output_files) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << prefix << workdir << separator;
  std::cerr << prefix << user_id << separator;
  if (hooks.empty()) {
    std::cerr << prefix << "hooks: []" << separator;
  } else {
    std::cerr << prefix << "hooks" << ": [";
    for (const auto &q: hooks) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (env.empty()) {
    std::cerr << prefix << "env: []" << separator;
  } else {
    std::cerr << prefix << "env" << ": [";
    for (const auto &q: env) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (deps.empty()) {
    std::cerr << prefix << "deps: []" << separator;
  } else {
    std::cerr << prefix << "deps" << ": [";
    for (const auto &q: deps) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  if (projects.empty()) {
    std::cerr << prefix << "projects: []" << separator;
  } else {
    std::cerr << prefix << "projects" << ": [";
    for (const auto &q: projects) {
      std::cerr << q << ",";
    }
    std::cerr << "]" << separator;
  }
  std::cerr << prefix << account_id << separator;
  std::cerr << prefix << gang_id << separator;
  std::cerr << prefix << execution_path << separator;
  std::cerr << prefix << script_content << separator;
  if (request.empty()) {
    std::cerr << prefix << "request: []" << separator;
  } else {
    std::cerr << prefix << "request" << ": [";
    for (const auto &q: request) {
      q.print(prefix, separator);
    }
    std::cerr << "]" << separator;
  }
  if (resources.empty()) {
    std::cerr << prefix << "resources: []" << separator;
  } else {
    std::cerr << prefix << "resources" << ": [";
    for (const auto &q: resources) {
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

