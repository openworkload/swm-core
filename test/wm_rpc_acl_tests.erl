-module(wm_rpc_acl_tests).

-include_lib("eunit/include/eunit.hrl").
-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_rpc_acl_tests

-spec allowed_node_mesh_test() -> ok.
allowed_node_mesh_test() ->
    ?assert(wm_rpc_acl:allowed(node, wm_compute, job_arrived)),
    ?assert(wm_rpc_acl:allowed(node, wm_pinger, route)),
    ?assert(wm_rpc_acl:allowed(node, wm_pinger, recv)),
    ?assert(wm_rpc_acl:allowed(node, wm_conf, sync_schema_request)),
    ?assert(wm_rpc_acl:allowed(node, wm_db, reset_db_request)),
    ?assert(wm_rpc_acl:allowed(node, wm_factory_commit, send_event)),
    ?assert(wm_rpc_acl:allowed(node, wm_api, recv)),
    ?assertNot(wm_rpc_acl:allowed(node, wm_admin, global)),
    ?assertNot(wm_rpc_acl:allowed(node, wm_admin, node)),
    ok.

-spec allowed_admin_only_wm_admin_test() -> ok.
allowed_admin_only_wm_admin_test() ->
    ?assert(wm_rpc_acl:allowed(admin, wm_admin, global)),
    ?assert(wm_rpc_acl:allowed(admin, wm_admin, node)),
    ?assert(wm_rpc_acl:allowed(admin, wm_admin, user)),
    ?assertNot(wm_rpc_acl:allowed(admin, wm_db, reset_db_request)),
    ?assertNot(wm_rpc_acl:allowed(admin, wm_compute, job_arrived)),
    ?assertNot(wm_rpc_acl:allowed(admin, wm_conf, sync_schema_request)),
    ok.

-spec allowed_user_and_unknown_deny_all_test() -> ok.
allowed_user_and_unknown_deny_all_test() ->
    ?assertNot(wm_rpc_acl:allowed(user, wm_admin, global)),
    ?assertNot(wm_rpc_acl:allowed(user, wm_compute, job_arrived)),
    ?assertNot(wm_rpc_acl:allowed(user, wm_db, reset_tabs_request)),
    ?assertNot(wm_rpc_acl:allowed(unknown, wm_admin, global)),
    ?assertNot(wm_rpc_acl:allowed(unknown, wm_pinger, route)),
    ok.

-spec is_admin_acl_test() -> ok.
is_admin_acl_test() ->
    ?assert(wm_rpc_acl:is_admin_acl("admin")),
    ?assert(wm_rpc_acl:is_admin_acl("admin,other")),
    ?assert(wm_rpc_acl:is_admin_acl(" other , admin ")),
    ?assertNot(wm_rpc_acl:is_admin_acl("")),
    ?assertNot(wm_rpc_acl:is_admin_acl("user")),
    ?assertNot(wm_rpc_acl:is_admin_acl(undefined)),
    ok.

-spec is_admin_user_acl_and_env_test() -> ok.
is_admin_user_acl_and_env_test() ->
    AdminUser =
        wm_entity:set([{id, "id-admin"}, {name, "alice"}, {acl, "admin"}], wm_entity:new(user)),
    NormalUser =
        wm_entity:set([{id, "id-user"}, {name, "bob"}, {acl, ""}], wm_entity:new(user)),
    ?assert(wm_rpc_acl:is_admin_user(AdminUser)),
    ?assertNot(wm_rpc_acl:is_admin_user(NormalUser)),
    Old = os:getenv("SWM_ADMIN_USER"),
    true = os:putenv("SWM_ADMIN_USER", "bob"),
    try
        ?assert(wm_rpc_acl:is_admin_user(NormalUser))
    after
        case Old of
            false ->
                os:unsetenv("SWM_ADMIN_USER");
            _ ->
                os:putenv("SWM_ADMIN_USER", Old)
        end
    end,
    ok.

-spec classify_uid_with_meck_test() -> ok.
classify_uid_with_meck_test() ->
    meck:new(wm_conf, [passthrough, no_link]),
    try
        NodeId = "node-uid-1",
        AdminId = "admin-uid-1",
        UserId = "user-uid-1",
        NodeRec = wm_entity:set([{id, NodeId}, {name, "n1"}], wm_entity:new(node)),
        AdminRec =
            wm_entity:set([{id, AdminId}, {name, "adm"}, {acl, "admin"}], wm_entity:new(user)),
        UserRec =
            wm_entity:set([{id, UserId}, {name, "usr"}, {acl, ""}], wm_entity:new(user)),
        meck:expect(wm_conf,
                    select,
                    fun(node, {id, Id}) when Id =:= NodeId ->
                           {ok, NodeRec};
                       (node, {id, _}) ->
                           {error, not_found};
                       (user, {id, Id}) when Id =:= AdminId ->
                           {ok, AdminRec};
                       (user, {id, Id}) when Id =:= UserId ->
                           {ok, UserRec};
                       (user, {id, _}) ->
                           {error, not_found};
                       (Tab, Key) ->
                           meck:passthrough([Tab, Key])
                    end),
        ?assertEqual(node, wm_rpc_acl:classify_uid(NodeId)),
        ?assertEqual(admin, wm_rpc_acl:classify_uid(AdminId)),
        ?assertEqual(user, wm_rpc_acl:classify_uid(UserId)),
        %% Unknown UID with no spool match -> unknown
        true = os:unsetenv("SWM_SPOOL"),
        ?assertEqual(unknown, wm_rpc_acl:classify_uid("no-such-uid")),
        ?assertEqual(unknown, wm_rpc_acl:classify_uid(unknown))
    after
        meck:unload(wm_conf)
    end,
    ok.
