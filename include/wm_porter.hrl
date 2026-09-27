% Porter stdin/stdout binary framing (must stay in sync with c_src/porter/)
-define(PORTER_COMMAND_RUN, 1).
-define(PORTER_COMMAND_CTRL_REPLY, 2).
-define(PORTER_DATA_TYPES_COUNT, 2).
-define(PORTER_DATA_TYPE_USERS, 0).
-define(PORTER_DATA_TYPE_JOBS, 1).
