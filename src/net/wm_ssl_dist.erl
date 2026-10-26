%%% @doc TLS verify_fun for Erlang distribution (inet_tls).
%%% Accept only peer certificates with the node profile (clientAuth+serverAuth).
-module(wm_ssl_dist).

-export([verify_fun/3]).

-include_lib("public_key/include/public_key.hrl").

%% @doc ssl verify_fun MFA: reject non-node end-entity certs after CA path ok.
-spec verify_fun(term(),
                 {bad_cert, term()} | {extension, term()} | valid | valid_peer,
                 term()) ->
                    {valid | fail | unknown, term()} | {fail, term()}.
verify_fun(_OtpCert, {bad_cert, _} = Reason, _State) ->
    {fail, Reason};
verify_fun(_OtpCert, {extension, _}, State) ->
    {unknown, State};
verify_fun(_OtpCert, valid, State) ->
    {valid, State};
verify_fun(OtpCert, valid_peer, State) ->
    case peer_is_node(OtpCert) of
        true ->
            {valid, State};
        false ->
            {fail, {bad_cert, non_node_cert}}
    end.

-spec peer_is_node(term()) -> boolean().
peer_is_node(#'OTPCertificate'{} = Cert) ->
    wm_cert:profile(Cert) =:= node;
peer_is_node(Der) when is_binary(Der) ->
    try
        wm_cert:profile_from_der(Der) =:= node
    catch
        _:_ ->
            false
    end;
peer_is_node(_) ->
    false.
