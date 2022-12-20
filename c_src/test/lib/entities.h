#include <gtest/gtest.h>
#include "gmock/gmock-matchers.h"

#include "wm_job.h"
#include "wm_node.h"
#include "wm_resource.h"
#include "wm_scheduler_result.h"
#include "wm_entity_utils.h"
#include "wm_process.h"

using ::testing::ElementsAre;

TEST(Node, construct) {
  static const int entity_tuple_arity = 20;

  ei_x_buff x;
  EXPECT_EQ(ei_x_new(&x), 0);

  EXPECT_EQ(ei_x_encode_tuple_header(&x, entity_tuple_arity), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "node"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "the id"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "the name"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "the host"), 0);
  EXPECT_EQ(ei_x_encode_ulonglong(&x, 10001), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "the parent"), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "up"), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "busy"), 0);

  EXPECT_EQ(ei_x_encode_list_header(&x, 3), 0);  // roles
  {
    EXPECT_EQ(ei_x_encode_ulonglong(&x, 2), 0);
    EXPECT_EQ(ei_x_encode_ulonglong(&x, 3), 0);
    EXPECT_EQ(ei_x_encode_ulonglong(&x, 4), 0);
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);

  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // resources
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 8), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "resource"), 0);
      EXPECT_EQ(ei_x_encode_string(&x, "mem"), 0);
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 128000000), 0);
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // hooks
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // properties
      EXPECT_EQ(ei_x_encode_map_header(&x, 0), 0);   // prices
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 0), 0);     // usage time
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // resources
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);

  EXPECT_EQ(ei_x_encode_empty_list(&x), 0); // properties

  EXPECT_EQ(ei_x_encode_atom(&x, "partition"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "subdivision-id"), 0);
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // malfunctions
  EXPECT_EQ(ei_x_encode_string(&x, "a comment"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "remote-id"), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "false"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "gateway"), 0);
  EXPECT_EQ(ei_x_encode_map_header(&x, 2), 0);   // prices
  {
    EXPECT_EQ(ei_x_encode_string(&x, "account-1"), 0);
    EXPECT_EQ(ei_x_encode_double(&x, 0.0), 0);
    EXPECT_EQ(ei_x_encode_string(&x, "account-2"), 0);
    EXPECT_EQ(ei_x_encode_double(&x, 42.12), 0);
  }
  EXPECT_EQ(ei_x_encode_ulonglong(&x, 5), 0);

  int index = 0;
  const auto entity = swm::SwmNode(x.buff, index);

  EXPECT_EQ(entity.get_id(), "the id");
  EXPECT_EQ(entity.get_name(), "the name");
  EXPECT_EQ(entity.get_host(), "the host");
  EXPECT_EQ(entity.get_api_port(), 10001ul);
  EXPECT_EQ(entity.get_parent(), "the parent");
  EXPECT_EQ(entity.get_state_power(), "up");
  EXPECT_EQ(entity.get_state_alloc(), "busy");
  EXPECT_THAT(entity.get_roles(), ElementsAre(2, 3, 4));

  const auto resources = entity.get_resources();
  EXPECT_EQ(resources.size(), 1ul);
  EXPECT_EQ(resources[0].get_name(), "mem");
  EXPECT_EQ(resources[0].get_count(), 128000000ul);

  EXPECT_EQ(entity.get_subdivision(), "partition");
  EXPECT_EQ(entity.get_subdivision_id(), "subdivision-id");
  EXPECT_EQ(entity.get_comment(), "a comment");
  EXPECT_EQ(entity.get_remote_id(), "remote-id");
  EXPECT_EQ(entity.get_is_template(), "false");
  EXPECT_EQ(entity.get_gateway(), "gateway");
  EXPECT_EQ(entity.get_revision(), 5ul);

  const auto prices = entity.get_prices();
  EXPECT_EQ(prices.size(), 2ul);
  const auto found1 = prices.find("account-1");
  const auto found2 = prices.find("account-2");
  EXPECT_TRUE(found1 != prices.end());
  EXPECT_TRUE(found2 != prices.end());
  EXPECT_DOUBLE_EQ(stod(found1->second), 0.0);
  EXPECT_DOUBLE_EQ(stod(found2->second), 42.12);

  EXPECT_EQ(ei_x_free(&x), 0);
}

TEST(SchedulerResult, construct) {
  static const int entity_tuple_arity = 8;

  ei_x_buff x;
  EXPECT_EQ(ei_x_new(&x), 0);

  EXPECT_EQ(ei_x_encode_tuple_header(&x, entity_tuple_arity), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "scheduler_result"), 0);

  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // timetables
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 4), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "timetable"), 0);
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 42), 0);
      EXPECT_EQ(ei_x_encode_string(&x, "job-id"), 0);
      EXPECT_EQ(ei_x_encode_list_header(&x, 3), 0);  // job_nodes
      {
        EXPECT_EQ(ei_x_encode_string(&x, "node-id-1"), 0);
        EXPECT_EQ(ei_x_encode_string(&x, "node-id-2"), 0);
        EXPECT_EQ(ei_x_encode_string(&x, "node-id-3"), 0);
      }
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);

  EXPECT_EQ(ei_x_encode_list_header(&x, 2), 0);  // metrics
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 4), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "metric"), 0);
      EXPECT_EQ(ei_x_encode_atom(&x, "metric1"), 0);
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 0), 0);
      EXPECT_EQ(ei_x_encode_double(&x, 731.34701), 0);
    }
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 3), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "metric"), 0);
      EXPECT_EQ(ei_x_encode_atom(&x, "metric2"), 0);
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 567), 0);
      EXPECT_EQ(ei_x_encode_double(&x, 0.0), 0);
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);

  EXPECT_EQ(ei_x_encode_string(&x, "request-id"), 0);
  EXPECT_EQ(ei_x_encode_ulonglong(&x, 3), 0);
  EXPECT_EQ(ei_x_encode_double(&x, 12.4), 0);
  EXPECT_EQ(ei_x_encode_double(&x, 1.0), 0);
  EXPECT_EQ(ei_x_encode_double(&x, 0.5), 0);

  int index = 0;
  const auto entity = swm::SwmSchedulerResult(x.buff, index);

  const auto timetable_rows = entity.get_timetable();
  EXPECT_EQ(timetable_rows.size(), 1ul);
  EXPECT_EQ(timetable_rows[0].get_start_time(), 42ul);
  EXPECT_EQ(timetable_rows[0].get_job_id(), "job-id");
  EXPECT_THAT(timetable_rows[0].get_job_nodes(), ElementsAre("node-id-1", "node-id-2", "node-id-3"));

  const auto metrics = entity.get_metrics();
  EXPECT_EQ(metrics.size(), 2ul);
  EXPECT_EQ(metrics[0].get_name(), "metric1");
  EXPECT_EQ(metrics[0].get_value_integer(), 0ul);
  EXPECT_EQ(metrics[0].get_value_float64(), 731.34701);
  EXPECT_EQ(metrics[1].get_name(), "metric2");
  EXPECT_EQ(metrics[1].get_value_integer(), 567ul);
  EXPECT_EQ(metrics[1].get_value_float64(), 0.0);

  EXPECT_EQ(entity.get_request_id(), "request-id");
  EXPECT_EQ(entity.get_status(), 3ul);
  EXPECT_EQ(entity.get_astro_time(), 12.4);
  EXPECT_EQ(entity.get_idle_time(), 1.0);
  EXPECT_EQ(entity.get_work_time(), 0.5);
}

TEST(Process, construct) {
  static const int entity_tuple_arity = 6;

  ei_x_buff x;
  EXPECT_EQ(ei_x_new(&x), 0);

  EXPECT_EQ(ei_x_encode_tuple_header(&x, entity_tuple_arity), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "process"), 0);
  EXPECT_EQ(ei_x_encode_longlong(&x, 45521), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "R"), 0);
  EXPECT_EQ(ei_x_encode_longlong(&x, -1), 0);
  EXPECT_EQ(ei_x_encode_longlong(&x, 9), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "comment"), 0);

  int index = 0;
  const auto entity = swm::SwmProcess(x.buff, index);

  EXPECT_EQ(entity.get_pid(), 45521);
  EXPECT_EQ(entity.get_state(), "R");
  EXPECT_EQ(entity.get_exitcode(), -1);
  EXPECT_EQ(entity.get_signal(), 9);
  EXPECT_EQ(entity.get_comment(), "comment");
}

TEST(Job, construct) {
  static const int entity_tuple_arity = 34;

  ei_x_buff x;
  EXPECT_EQ(ei_x_new(&x), 0);

  EXPECT_EQ(ei_x_encode_tuple_header(&x, entity_tuple_arity), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "job"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "7873a946-d85d-11ec-8529-6fdf37248ceb"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "Job name"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "cluster-id"), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 3), 0);  // nodes
  {
    EXPECT_EQ(ei_x_encode_string(&x, "node-id-1"), 0);
    EXPECT_EQ(ei_x_encode_string(&x, "node-id-2"), 0);
    EXPECT_EQ(ei_x_encode_string(&x, "node-id-3"), 0);
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "Q"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "2022-05-22T20:01:48"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "2022-05-22T20:00:34"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "2022-05-22T20:02:00"), 0);
  EXPECT_EQ(ei_x_encode_longlong(&x, 2), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "job-stdin"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "job-stdout"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "job-stderr"), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 2), 0);  // input_files
  {
    EXPECT_EQ(ei_x_encode_string(&x, "/path/to/file1"), 0);
    EXPECT_EQ(ei_x_encode_string(&x, "/path/to/file2"), 0);
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 2), 0);  // output_files
  {
    EXPECT_EQ(ei_x_encode_string(&x, "/path/to/file3"), 0);
    EXPECT_EQ(ei_x_encode_string(&x, "/path/to/file4"), 0);
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "workdir"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "user-id"), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // hooks
  {
    EXPECT_EQ(ei_x_encode_string(&x, "hook-id-1"), 0);
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // env
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 2), 0);
    {
      EXPECT_EQ(ei_x_encode_string(&x, "HOME"), 0);
      EXPECT_EQ(ei_x_encode_string(&x, "/home/dude"), 0);
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // deps
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 2), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "ok"), 0);
      EXPECT_EQ(ei_x_encode_string(&x, "job-id-42"), 0);
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // projects
  EXPECT_EQ(ei_x_encode_string(&x, "account-id-2"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "gang-id-4"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "/home/dude/exec1"), 0);
  EXPECT_EQ(ei_x_encode_string(&x, "#!/bin/sh\nsleep120\nhostname\n"), 0);
  EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // request
  {
    EXPECT_EQ(ei_x_encode_tuple_header(&x, 8), 0);
    {
      EXPECT_EQ(ei_x_encode_atom(&x, "resource"), 0);
      EXPECT_EQ(ei_x_encode_string(&x, "node"), 0);
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 1), 0);
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // hooks
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // properties
      EXPECT_EQ(ei_x_encode_map_header(&x, 0), 0);   // prices
      EXPECT_EQ(ei_x_encode_ulonglong(&x, 0), 0);     // usage time
      EXPECT_EQ(ei_x_encode_list_header(&x, 2), 0);  // resources
      {
        EXPECT_EQ(ei_x_encode_tuple_header(&x, 8), 0);
        {
          EXPECT_EQ(ei_x_encode_atom(&x, "resource"), 0);
          EXPECT_EQ(ei_x_encode_string(&x, "mem"), 0);
          EXPECT_EQ(ei_x_encode_ulonglong(&x, 1234567), 0);
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // hooks
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // properties
          EXPECT_EQ(ei_x_encode_map_header(&x, 0), 0); // prices
          EXPECT_EQ(ei_x_encode_ulonglong(&x, 0), 0);  // usage time
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // resources
        }
        EXPECT_EQ(ei_x_encode_tuple_header(&x, 8), 0);
        {
          EXPECT_EQ(ei_x_encode_atom(&x, "resource"), 0);
          EXPECT_EQ(ei_x_encode_string(&x, "flavor"), 0);
          EXPECT_EQ(ei_x_encode_ulonglong(&x, 1), 0);
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // hooks
          EXPECT_EQ(ei_x_encode_list_header(&x, 1), 0);  // properties
          {
            EXPECT_EQ(ei_x_encode_tuple_header(&x, 2), 0);  // {value, "m1.tiny"}
            {
              EXPECT_EQ(ei_x_encode_atom(&x, "value"), 0);
              EXPECT_EQ(ei_x_encode_string(&x, "m1.tiny"), 0);
            }
          }
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
          EXPECT_EQ(ei_x_encode_map_header(&x, 0), 0); // prices
          EXPECT_EQ(ei_x_encode_ulonglong(&x, 0), 0);  // usage time
          EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // resources
        }
      }
      EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
    }
  }
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);
  EXPECT_EQ(ei_x_encode_empty_list(&x), 0);  // resources
  EXPECT_EQ(ei_x_encode_string(&x, "container-id-28"), 0);
  EXPECT_EQ(ei_x_encode_atom(&x, "true"), 0);  // relocatable
  EXPECT_EQ(ei_x_encode_ulong(&x, 1), 0);  // exit code
  EXPECT_EQ(ei_x_encode_ulong(&x, 15), 0);  // signal
  EXPECT_EQ(ei_x_encode_ulong(&x, 1500), 0);  // priority
  EXPECT_EQ(ei_x_encode_string(&x, "comment"), 0);
  EXPECT_EQ(ei_x_encode_ulong(&x, 0), 0);  // revision

  int index = 0;
  const auto entity = swm::SwmJob(x.buff, index);

  EXPECT_EQ(entity.get_id(), "7873a946-d85d-11ec-8529-6fdf37248ceb");
  EXPECT_EQ(entity.get_name(), "Job name");
  EXPECT_EQ(entity.get_cluster_id(), "cluster-id");
  EXPECT_THAT(entity.get_nodes(), ElementsAre("node-id-1", "node-id-2", "node-id-3"));
  EXPECT_EQ(entity.get_state(), "Q");
  EXPECT_EQ(entity.get_start_time(), "2022-05-22T20:01:48");
  EXPECT_EQ(entity.get_submit_time(), "2022-05-22T20:00:34");
  EXPECT_EQ(entity.get_end_time(), "2022-05-22T20:02:00");
  EXPECT_EQ(entity.get_duration(), 2ul);
  EXPECT_EQ(entity.get_job_stdin(), "job-stdin");
  EXPECT_EQ(entity.get_job_stdout(), "job-stdout");
  EXPECT_EQ(entity.get_job_stderr(), "job-stderr");
  EXPECT_THAT(entity.get_input_files(), ElementsAre("/path/to/file1", "/path/to/file2"));
  EXPECT_THAT(entity.get_output_files(), ElementsAre("/path/to/file3", "/path/to/file4"));
  EXPECT_EQ(entity.get_workdir(), "workdir");
  EXPECT_EQ(entity.get_user_id(), "user-id");
  EXPECT_THAT(entity.get_hooks(), ElementsAre("hook-id-1"));
  EXPECT_THAT(entity.get_env(), ElementsAre(std::pair("HOME", "/home/dude")));
  EXPECT_THAT(entity.get_deps(), ElementsAre(std::pair("ok", "job-id-42")));
  EXPECT_TRUE(entity.get_projects().empty());
  EXPECT_EQ(entity.get_account_id(), "account-id-2");
  EXPECT_EQ(entity.get_gang_id(), "gang-id-4");
  EXPECT_EQ(entity.get_execution_path(), "/home/dude/exec1");
  EXPECT_EQ(entity.get_script_content(), "#!/bin/sh\nsleep120\nhostname\n");

  const auto resources = entity.get_request();
  EXPECT_EQ(resources.size(), 1ul);
  EXPECT_EQ(resources[0].get_name(), "node");
  EXPECT_EQ(resources[0].get_count(), 1ul);

  const auto sub_resources = resources[0].get_resources();
  EXPECT_EQ(sub_resources.size(), 2ul);

  EXPECT_EQ(sub_resources[0].get_name(), "mem");
  EXPECT_EQ(sub_resources[0].get_count(), 1234567ul);
  EXPECT_TRUE(sub_resources[0].get_properties().empty());

  EXPECT_EQ(sub_resources[1].get_name(), "flavor");
  EXPECT_EQ(sub_resources[1].get_count(), 1ul);
  const auto props = sub_resources[1].get_properties();
  EXPECT_EQ(props.size(), 1ul);
  EXPECT_EQ(std::get<0>(props[0]), "value");

  std::string value;
  auto tmp_buf = std::get<1>(props[0]);
  ASSERT_EQ(swm::ei_buffer_to_str(tmp_buf, value), 0);
  EXPECT_EQ(value, "m1.tiny");

  EXPECT_TRUE(entity.get_resources().empty());
  EXPECT_EQ(entity.get_container(), "container-id-28");
  EXPECT_EQ(entity.get_relocatable(), "true");
  EXPECT_EQ(entity.get_exitcode(), 1ul);
  EXPECT_EQ(entity.get_signal(), 15ul);
  EXPECT_EQ(entity.get_priority(), 1500ul);
  EXPECT_EQ(entity.get_comment(), "comment");
  EXPECT_EQ(entity.get_revision(), 0ul);
}
