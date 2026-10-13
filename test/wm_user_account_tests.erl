-module(wm_user_account_tests).

-include_lib("eunit/include/eunit.hrl").

-include("../src/lib/wm_entity.hrl").

%% ./rebar3 eunit --module=wm_user_account_tests

-define(UID, "uid-member").
-define(OTHER, "uid-other").
-define(ACC_ID, "acc-1").
-define(ACC_NAME, "billing").

-spec user_on_account_users_list_test() -> ok.
user_on_account_users_list_test() ->
    Acc = wm_entity:set([{id, ?ACC_ID}, {name, ?ACC_NAME}, {users, [?UID]}, {admins, []}], wm_entity:new(account)),
    ?assert(wm_user:user_on_account(?UID, Acc)),
    ?assertNot(wm_user:user_on_account(?OTHER, Acc)),
    ok.

-spec user_on_account_admins_list_test() -> ok.
user_on_account_admins_list_test() ->
    Acc = wm_entity:set([{id, ?ACC_ID}, {name, ?ACC_NAME}, {users, []}, {admins, [?UID]}], wm_entity:new(account)),
    ?assert(wm_user:user_on_account(?UID, Acc)),
    ?assertNot(wm_user:user_on_account(?OTHER, Acc)),
    ok.

-spec assert_account_member_allow_test() -> ok.
assert_account_member_allow_test() ->
    Acc = wm_entity:set([{id, ?ACC_ID}, {name, ?ACC_NAME}, {admins, [?UID]}], wm_entity:new(account)),
    User = wm_entity:set([{id, ?UID}, {name, "member"}], wm_entity:new(user)),
    Job = wm_entity:set([{account_id, ?ACC_ID}], wm_entity:new(job)),
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                select,
                fun (account, {id, ?ACC_ID}) ->
                        {ok, Acc};
                    (Tab, Key) ->
                        meck:passthrough([Tab, Key])
                end),
    try
        ?assertMatch({ok, #job{account_id = ?ACC_ID}}, wm_user:assert_account_member(Job, User))
    after
        meck:unload(wm_conf)
    end,
    ok.

-spec assert_account_member_forbidden_test() -> ok.
assert_account_member_forbidden_test() ->
    Acc = wm_entity:set([{id, ?ACC_ID}, {name, ?ACC_NAME}, {admins, [?OTHER]}], wm_entity:new(account)),
    User = wm_entity:set([{id, ?UID}, {name, "member"}], wm_entity:new(user)),
    Job = wm_entity:set([{account_id, ?ACC_ID}], wm_entity:new(job)),
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                select,
                fun (account, {id, ?ACC_ID}) ->
                        {ok, Acc};
                    (Tab, Key) ->
                        meck:passthrough([Tab, Key])
                end),
    try
        ?assertEqual({error, forbidden}, wm_user:assert_account_member(Job, User))
    after
        meck:unload(wm_conf)
    end,
    ok.

-spec assert_account_member_not_found_test() -> ok.
assert_account_member_not_found_test() ->
    User = wm_entity:set([{id, ?UID}, {name, "member"}], wm_entity:new(user)),
    Job = wm_entity:set([{account_id, "nosuch"}], wm_entity:new(job)),
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                select,
                fun (account, {id, "nosuch"}) ->
                        {error, not_found};
                    (account, {name, "nosuch"}) ->
                        {error, not_found};
                    (Tab, Key) ->
                        meck:passthrough([Tab, Key])
                end),
    try
        ?assertEqual({error, not_found}, wm_user:assert_account_member(Job, User))
    after
        meck:unload(wm_conf)
    end,
    ok.

-spec assert_account_member_normalize_name_test() -> ok.
assert_account_member_normalize_name_test() ->
    %% Job still holds the account name; assert normalizes to UUID.
    Acc = wm_entity:set([{id, ?ACC_ID}, {name, ?ACC_NAME}, {users, [?UID]}], wm_entity:new(account)),
    User = wm_entity:set([{id, ?UID}, {name, "member"}], wm_entity:new(user)),
    Job = wm_entity:set([{account_id, ?ACC_NAME}], wm_entity:new(job)),
    meck:new(wm_conf, [passthrough]),
    meck:expect(wm_conf,
                select,
                fun (account, {id, ?ACC_NAME}) ->
                        {error, not_found};
                    (account, {name, ?ACC_NAME}) ->
                        {ok, Acc};
                    (Tab, Key) ->
                        meck:passthrough([Tab, Key])
                end),
    try
        ?assertMatch({ok, #job{account_id = ?ACC_ID}}, wm_user:assert_account_member(Job, User))
    after
        meck:unload(wm_conf)
    end,
    ok.
