#include <gtest/gtest.h>
#include "gmock/gmock-matchers.h"

#include "wm_node.h"
#include "wm_resource.h"
#include "wm_scheduler_result.h"
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
  EXPECT_EQ(ei_x_encode_map_header(&x, 0), 0);   // prices
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
