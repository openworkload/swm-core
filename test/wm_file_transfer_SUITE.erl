-module(wm_file_transfer_SUITE).

-export([suite/0, all/0, groups/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([transfer_empty/1, transfer_dir/1, transfer_file/1, transfer_long_dir_file/1, transfer_with_discontinue/1]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("kernel/include/file.hrl").

suite() ->
    [{timetrap, {seconds, 260}}].

all() ->
    [{group, common}].

groups() ->
    [{common, [], [transfer_empty, transfer_dir, transfer_file, transfer_long_dir_file, transfer_with_discontinue]}].

init_per_suite(Config) ->
    Result = application:ensure_all_started(swm),
    ct:print("Application swm has been started: ~p", [Result]),
    Config.

end_per_suite(Config) ->
    Config.

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, Config) ->
    Config.

transfer_empty(Config) ->
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    {ok, Ref1} = wm_file_transfer:upload(self(), "localhost", 1, [], [], #{via => ssh}),
    ok = wm_utils:await(Ref1, 2000),
    {ok, Ref2} = wm_file_transfer:upload(self(), "localhost", 1, <<>>, [], #{via => ssh}),
    ok = wm_utils:await(Ref2, 2000),
    {ok, Ref3} = wm_file_transfer:upload(self(), "localhost", 1, <<>>, <<>>, #{via => ssh}),
    ok = wm_utils:await(Ref3, 2000),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    {ok, Ref4} = wm_file_transfer:download(self(), "localhost", 1, [], [], #{via => ssh}),
    ok = wm_utils:await(Ref4, 2000),
    {ok, Ref5} = wm_file_transfer:download(self(), "localhost", 1, <<>>, [], #{via => ssh}),
    ok = wm_utils:await(Ref5, 2000),
    {ok, Ref6} = wm_file_transfer:download(self(), "localhost", 1, <<>>, <<>>, #{via => ssh}),
    ok = wm_utils:await(Ref6, 2000),
    ok.

transfer_dir(Config) ->
    Uniq = uniq(),
    BaseDir = base_dir(Config),
    Src = src(Uniq),
    Dst = dst(Uniq),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, []))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref1} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir, DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref1, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(filename:join(DstDir, Src))),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, []))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref2} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref2, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_directory("nested1a",
                                            [create_directory("nested2a", [create_directory("nested3a", [])]),
                                             create_directory("nested2b", []),
                                             create_directory("nested2c", [])])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref3} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref3, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, []))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref4} = wm_file_transfer:download(self(), "localhost", 1, SrcDir, DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref4, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(filename:join(DstDir, Src))),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_directory("nested1a",
                                            [create_directory("nested2a", [create_directory("nested3a", [])]),
                                             create_directory("nested2b", []),
                                             create_directory("nested2c", [])])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref5} = wm_file_transfer:download(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref5, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    ok.

transfer_file(Config) ->
    Uniq = uniq(),
    BaseDir = base_dir(Config),
    Src = src(Uniq),
    Dst = dst(Uniq),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_file("nested-f1a", 0)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref1} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref1, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_file("nested-f1a", 0),
                           create_file("nested-f1b", 1),
                           create_file("nested-f1b", 5)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref2} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref2, 10000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_directory("nested1a", []),
                           create_directory("nested1b", [create_file("nested-f2a", 1), create_file("nested-f2b", 1)]),
                           create_directory("nested1c",
                                            [create_directory("nested2c", [create_directory("nested2c", [])])]),
                           create_directory("nested1d",
                                            [create_directory("nested2d",
                                                              [create_file("nested-f2a", 1),
                                                               create_file("nested-f2b", 1),
                                                               create_directory("nested3d",
                                                                                [create_file("nested-f3a", 1),
                                                                                 create_file("nested-f3b", 1)])])]),
                           create_directory("nested1e",
                                            [create_directory("nested2e",
                                                              [create_directory("nested3e",
                                                                                [create_directory("nested4e",
                                                                                                  [create_directory("nested5e",
                                                                                                                    [create_directory("nested6e",
                                                                                                                                      [create_directory("nested7e",
                                                                                                                                                        [create_directory("nested8e",
                                                                                                                                                                          [create_directory("nested9e",
                                                                                                                                                                                            [create_file("nested-f10a",
                                                                                                                                                                                                         1)])])])])])])])])])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref3} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref3, 30000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_file("nested-f1a", 100), create_file("nested-f1a", 100)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref4} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref4, 120000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_file("nested-f1a", 0)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref5} = wm_file_transfer:download(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref5, 20000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_file("nested-f1a", 0),
                           create_file("nested-f1b", 1),
                           create_file("nested-f1b", 5)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref6} = wm_file_transfer:download(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref6, 20000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir =
        (create_directory(Src,
                          [create_directory("nested1a", []),
                           create_directory("nested1b", [create_file("nested-f2a", 1), create_file("nested-f2b", 1)]),
                           create_directory("nested1c",
                                            [create_directory("nested2c", [create_directory("nested2c", [])])]),
                           create_directory("nested1d",
                                            [create_directory("nested2d",
                                                              [create_file("nested-f2a", 1),
                                                               create_file("nested-f2b", 1),
                                                               create_directory("nested3d",
                                                                                [create_file("nested-f3a", 1),
                                                                                 create_file("nested-f3b", 1)])])]),
                           create_directory("nested1e",
                                            [create_directory("nested2e",
                                                              [create_directory("nested3e",
                                                                                [create_directory("nested4e",
                                                                                                  [create_directory("nested5e",
                                                                                                                    [create_directory("nested6e",
                                                                                                                                      [create_directory("nested7e",
                                                                                                                                                        [create_directory("nested8e",
                                                                                                                                                                          [create_directory("nested9e",
                                                                                                                                                                                            [create_file("nested-f10a",
                                                                                                                                                                                                         1)])])])])])])])])])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref7} = wm_file_transfer:download(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref7, 80000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_file("nested-f1a", 100), create_file("nested-f1a", 100)]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref8} = wm_file_transfer:download(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref8, 300000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    ok.

transfer_long_dir_file(Config) ->
    Uniq = uniq(),
    BaseDir = base_dir(Config),
    Src = src(Uniq),
    Dst = dst(Uniq),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_directory(rand(), [create_file(rand(), 10)])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref1} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref1, 20000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% DOWNLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_directory(rand(), [create_file(rand(), 10)])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref2} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    ok = wm_utils:await(Ref2, 20000),
    ?assertEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    ok.

transfer_with_discontinue(Config) ->
    Uniq = uniq(),
    BaseDir = base_dir(Config),
    Src = src(Uniq),
    Dst = dst(Uniq),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_directory(rand(), [create_file(rand(), 100)])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref1} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    timeout = wm_utils:await(Ref1, 200),
    {ok, Ref2} = wm_file_transfer:discontinue(self(), Ref1, false),
    ok = wm_utils:await(Ref2, 2000),
    timeout = wm_utils:await(Ref1, 2000),
    ?assertNotEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    %%----------------------------------
    %% UPLOAD
    %%----------------------------------
    SrcDir = (create_directory(Src, [create_directory(rand(), [create_file(rand(), 100)])]))(BaseDir),
    DstDir = (create_directory(Dst, []))(BaseDir),
    {ok, Ref3} = wm_file_transfer:upload(self(), "localhost", 1, SrcDir ++ "/", DstDir, #{via => ssh}),
    timeout = wm_utils:await(Ref3, 200),
    {ok, Ref4} = wm_file_transfer:discontinue(self(), Ref3, true),
    ok = wm_utils:await(Ref4, 2000),
    timeout = wm_utils:await(Ref3, 2000),
    ?assertNotEqual(list_recursive_directory(SrcDir), list_recursive_directory(DstDir)),
    ?assertEqual({ok, []}, wm_file_transfer:get_transfers()),
    wm_file_utils:delete_directory(SrcDir),
    wm_file_utils:delete_directory(DstDir),
    ok.

%% ============================================================================
%% Auxiliary
%% ============================================================================

%% 64b
-define(FISH,
        <<"Lorem ipsum dolor sit amet, consectetur "
          "adipiscing elit, sed... ">>).
%% 1mb
-define(WHALE, lists:duplicate(16384, ?FISH)).
-define(ALPHABET,
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRS"
        "TUVWXYZ1234567890@#$&~%*()[]{}'\".,:;><` "
        "").

base_dir(Config) ->
    proplists:get_value(priv_dir, Config).

uniq() ->
    integer_to_list(erlang:unique_integer([positive])).

rand() ->
    N = length(?ALPHABET),
    [lists:nth(
         rand:uniform(N), ?ALPHABET)
     || _ <- lists:seq(1, 127)].

src(Uniq) ->
    "src" ++ Uniq.

dst(Uniq) ->
    "dst" ++ Uniq.

-spec create_file(string() | binary(), pos_integer()) -> fun((...) -> term()).
create_file(Name, Size) ->
    fun(Dir) ->
       ok = filelib:ensure_dir(Dir),
       FileName = filename:join(Dir, Name),
       {ok, File} = file:open(FileName, [raw, write]),
       [file:write(File, ?WHALE) || _ <- lists:seq(1, Size)],
       ok = file:sync(File),
       _ = file:close(File),
       _ = file:close(File),
       ok
    end.

-spec create_directory(string() | binary(), [fun((...) -> term())]) -> fun((...) -> term()).
create_directory(Name, CreateFuns) ->
    fun(Dir) ->
       DirName = filename:join(Dir, Name),
       ok = file:make_dir(DirName),
       [CreateFun(DirName) || CreateFun <- CreateFuns],
       DirName
    end.

-spec list_recursive_directory(string() | binary()) ->
                                  [#{name := string() | binary(),
                                     size := pos_integer(),
                                     type := atom(),
                                     access := atom(),
                                     mode := pos_integer(),
                                     uid := pos_integer(),
                                     gid := pos_integer()}].
list_recursive_directory(Dir) ->
    F = fun(FileName) ->
           {ok, Info} = file:read_file_info(FileName),
           #{name =>
                 lists:flatten(
                     string:replace(FileName, Dir, ".")),
             size => Info#file_info.size,
             type => Info#file_info.type,
             access => Info#file_info.access,
             mode => Info#file_info.mode,
             uid => Info#file_info.uid,
             gid => Info#file_info.gid}
        end,
    Xs = wm_file_utils:list_directory(Dir, _Recursive = true),
    lists:sort(
        lists:map(F, flatten(Xs))).

flatten(X) ->
    lists:reverse(flatten(X, [])).

flatten([], Acc) ->
    Acc;
flatten([H | T], Acc) when is_integer(H) ->
    flatten([], [[H | T] | Acc]);
flatten([H | T], Acc) when is_list(H) ->
    flatten(T, flatten(H, Acc));
flatten([H | T], Acc) ->
    flatten(T, [H | Acc]).
