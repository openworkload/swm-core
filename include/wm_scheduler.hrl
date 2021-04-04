% Scheduler data types and commands
-define(COMMAND_SCHEDULE, 0).
-define(DATA_TYPE_SCHEDULERS, 0).
-define(DATA_TYPE_RH, 1).
-define(DATA_TYPE_JOBS, 2).
-define(DATA_TYPE_GRID, 3).
-define(DATA_TYPE_CLUSTERS, 4).
-define(DATA_TYPE_PARTITIONS, 5).
-define(DATA_TYPE_NODES, 6).
-define(TOTAL_DATA_TYPES, 7).
% Scheduler default parameters
-define(SCHEDULE_START_TIMEOUT, 5000).
-define(SCHEDULE_COMM_TIMEOUT, 30000).
% Porter commands and data types
-define(PORTER_COMMAND_RUN, 1).
-define(PORTER_DATA_TYPES_COUNT, 2).
-define(PORTER_DATA_TYPE_USERS, 0).
-define(PORTER_DATA_TYPE_JOBS, 1).
% Job states
-define(JOB_STATE_RUNNING, "E").
-define(JOB_STATE_QUEUED, "Q").
-define(JOB_STATE_WAITING, "W").
-define(JOB_STATE_FINISHED, "F").
-define(JOB_STATE_ERROR, "E").
-define(JOB_STATE_TRANSFERRING, "T").
-define(JOB_STATE_CANCELLED, "C").
