-module(wm_cert).

-export([create/3, get_uid/1]).

-include_lib("public_key/include/public_key.hrl").
-include_lib("public_key/include/OTP-PUB-KEY.hrl").

-define(OPENSSL, "openssl").
-define(SSH_KEYGEN, "ssh-keygen").
-define(SECUREDIR, "secure").
-define(USERSDIR, "users").
-define(CAGRIDDIR, "grid").
-define(CACLUSTERDIR, "cluster").
-define(ENV_SPOOL, "SWM_SPOOL").
-define(ENV_UNIT, "SWM_UNIT_NAME").
-define(ENV_ORG, "SWM_ORG_NAME").
-define(ENV_LOCALITY, "SWM_LOCALITY").
-define(ENV_COUNTRY, "SWM_COUNTRY").
-define(ENV_EMAIL, "SWM_ADMIN_EMAIL").

-record(dn,
        {commonName :: string(),
         organizationalUnitName :: string(),
         organizationName :: string(),
         localityName :: string(),
         countryName :: string(),
         emailAddress :: string(),
         id :: string()}).

%TODO Put IDs of grid, cluster and node into there CA/certificates

%% ============================================================================
%% API functions
%% ============================================================================

%% @doc Create a root (grid) CA to sign intermediate (cluster) CAs
-spec create(atom(), string(), string()) -> ok | {error, string()}.
create(grid, GridID, _) ->
    create_grid_ca(GridID);
%% @doc Create an intermediate (cluster) CA signed by a root (grid) CA
create(cluster, ClusterID, Name) ->
    create_cluster_ca(ClusterID, Name);
%% @doc Create intermediate CA signed by root CA
create(node, NodeID, Name) ->
    create_node_cert(NodeID, Name);
%% @doc Create user certificate signed by intermediate CA
create(user, UserID, Name) ->
    create_user_cert(UserID, Name);
%% @doc Create ssh host keys - rsa, dsa, ecdsa
create(host, _, Name) ->
    create_host_key(Name).

-spec get_uid(term()) -> string().
get_uid(Cert) ->
    do_get_altname(Cert).

%% ============================================================================
%% Implementation functions
%% ============================================================================

-spec create_grid_ca(string()) -> ok.
create_grid_ca(GridID) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    Request = req_cnf(ask_ca_dn(GridID, cagrid_dirname()), SecureDir),
    ok = filelib:ensure_dir(SecureDir),
    create_rnd(SpoolDir, secure_dirname()),
    create_ca_dir(SecureDir, cagrid_dirname(), ca_cnf(cagrid_dirname())),
    create_self_signed_cert(SecureDir, openssl_cmd(), cagrid_dirname(), Request).

-spec create_cluster_ca(string(), string()) -> atom().
create_cluster_ca(ClusterID, Name) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    RootCADir = filename:join([SecureDir, cagrid_dirname()]),
    CADir = filename:join([SecureDir, Name]),
    CnfFile = filename:join([CADir, "req.cnf"]),
    KeyFile = filename:join([CADir, "private", "key.pem"]),
    ReqFile = filename:join([CADir, "req.pem"]),
    CertFile = filename:join([CADir, "cert.pem"]),
    Request = req_cnf(ask_ca_dn(ClusterID, Name), CADir),
    create_ca_dir(SecureDir, Name, ca_cnf(Name)),
    create_rnd(SpoolDir, secure_dirname()),
    file:write_file(CnfFile, Request),
    create_req(SecureDir, openssl_cmd(), CnfFile, KeyFile, ReqFile),
    sign_req(SecureDir, openssl_cmd(), RootCADir, "ca_cert", ReqFile, CertFile),
    remove_rnd(SecureDir, secure_dirname()).

-spec create_node_cert(string(), string()) -> atom().
create_node_cert(NodeID, CommonName) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    KeysDir = filename:join([SecureDir, "node"]),
    CnfFile = filename:join([KeysDir, "req.cnf"]),
    KeyFile = filename:join([KeysDir, "key.pem"]),
    ReqFile = filename:join([KeysDir, "req.pem"]),
    CertFile = filename:join([KeysDir, "cert.pem"]),
    CADir = filename:join([SecureDir, cacluster_dirname()]),
    Request = req_cnf(ask_ca_dn(NodeID, CommonName), KeysDir),
    ok = filelib:ensure_dir(KeysDir),
    create_dirs(SecureDir, ["node"]),
    create_rnd(SecureDir, "node"),
    file:write_file(CnfFile, Request),
    create_req(SecureDir, openssl_cmd(), CnfFile, KeyFile, ReqFile),
    sign_req(SecureDir, openssl_cmd(), CADir, "user_cert", ReqFile, CertFile),
    remove_rnd(SecureDir, "node").

-spec create_user_cert(string(), string()) -> atom().
create_user_cert(UserID, Name) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    create_cert(SpoolDir, Name, UserID, users_dirname()).

-spec create_host_key(string) -> atom().
create_host_key(Name) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    KeysDir = filename:join([SecureDir, Name]),
    RSAKey = filename:join([KeysDir, "ssh_host_rsa_key"]),
    DSAKey = filename:join([KeysDir, "ssh_host_dsa_key"]),
    ECDSAKey = filename:join([KeysDir, "ssh_host_ecdsa_key"]),
    case filelib:ensure_dir(KeysDir) of
        ok ->
            create_dirs(SecureDir, [Name]),
            generate_host_key(KeysDir, ssh_keygen_cmd(), "rsa", RSAKey),
            generate_host_key(KeysDir, ssh_keygen_cmd(), "dsa", DSAKey),
            generate_host_key(KeysDir, ssh_keygen_cmd(), "ecdsa", ECDSAKey);
        {error, eacces} ->
            io:format(standard_error, "No access to ~p~n", [KeysDir])
    end.


%% ============================================================================
%% Auxiliary functions
%% ============================================================================

-spec create_cert(string(), string(), string(), string()) -> atom().
create_cert(SpoolDir, Name, ID, DirName) ->
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    ParentDir = filename:join([SecureDir, DirName]),
    KeysDir = filename:join([ParentDir, Name]),
    CnfFile = filename:join([KeysDir, "req.cnf"]),
    KeyFile = filename:join([KeysDir, "key.pem"]),
    ReqFile = filename:join([KeysDir, "req.pem"]),
    CertFile = filename:join([KeysDir, "cert.pem"]),
    CADir = filename:join([SecureDir, cacluster_dirname()]),
    Request = req_cnf(ask_ca_dn(ID, Name), KeysDir),
    create_dirs(SecureDir, [users_dirname()]),
    filelib:ensure_dir(KeysDir),
    create_dirs(ParentDir, [Name]),
    create_rnd(ParentDir, Name),
    file:write_file(CnfFile, Request),
    create_req(SecureDir, openssl_cmd(), CnfFile, KeyFile, ReqFile),
    sign_req(SecureDir, openssl_cmd(), CADir, "user_cert", ReqFile, CertFile),
    remove_rnd(ParentDir, KeysDir).

-spec ask(string(), string()) -> string().
ask(Name, DefaultEnv) ->
    case os:getenv(DefaultEnv) of
        X when X == false; X == [] ->
            wm_utils:trail_newline(
                io:get_line(Name ++ ": "));
        Value ->
            Value
    end.

-spec ask_ca_dn(string(), string()) -> #dn{}.
ask_ca_dn(ID, CommonName) ->
    #dn{commonName = CommonName,
        id = ID,
        organizationalUnitName = ask("Organizational Unit Name", ?ENV_UNIT),
        organizationName = ask("Organization Name", ?ENV_ORG),
        localityName = ask("Locality Name", ?ENV_LOCALITY),
        countryName = ask("Country Name", ?ENV_COUNTRY),
        emailAddress = ask("Email Address", ?ENV_EMAIL)}.

-spec create_self_signed_cert(string(), string(), string(), list()) -> ok.
create_self_signed_cert(SecureDir, OpenSSLCmd, CAName, Cnf) ->
    CADir = filename:join([SecureDir, CAName]),
    CnfFile = filename:join([CADir, "req.cnf"]),
    KeyFile = filename:join([CADir, "private", "key.pem"]),
    CertFile = filename:join([CADir, "cert.pem"]),
    Cmd = [OpenSSLCmd, " req -new -x509 -days 365 -config ", CnfFile, " -keyout ", KeyFile, " -out ", CertFile],
    Env = [{"ROOTDIR", SecureDir}],
    file:write_file(CnfFile, Cnf),
    cmd(Cmd, Env).

-spec create_ca_dir(string(), string(), list()) -> ok.
create_ca_dir(KeysRoot, CAName, Cnf) ->
    CADir = filename:join([KeysRoot, CAName]),
    filelib:ensure_dir(KeysRoot),
    filelib:ensure_dir(CADir),
    create_dirs(CADir, ["certs", "crl", "newcerts", "private"]),
    create_rnd(KeysRoot, filename:join([CAName, "private"])),
    create_files(CADir, [{"serial", "01\n"}, {"index.txt", ""}, {"ca.cnf", Cnf}]).

-spec create_req(string(), string(), string(), string(), string()) -> ok.
create_req(ReqDir, OpenSSLCmd, CnfFile, KeyFile, ReqFile) ->
    io:format("~s: ~s~n", ["ReqDir", ReqDir]),
    io:format("~s: ~s~n", ["OpenSSLCmd", OpenSSLCmd]),
    io:format("~s: ~s~n", ["CnfFile", CnfFile]),
    io:format("~s: ~s~n", ["KeyFile", KeyFile]),
    io:format("~s: ~s~n", ["ReqFile", ReqFile]),
    Cmd = [OpenSSLCmd, " req -new -config ", CnfFile, " -keyout ", KeyFile, " -out ", ReqFile],
    Env = [{"ROOTDIR", ReqDir}],
    cmd(Cmd, Env).

-spec sign_req(string(), string(), string(), string(), string(), string()) -> ok.
sign_req(RootDir, OpenSSLCmd, CADir, Ext, ReqFile, CertFile) ->
    CACnfFile = filename:join([CADir, "ca.cnf"]),
    Cmd = [OpenSSLCmd,
           " ca -batch -utf8 -config ",
           CACnfFile,
           " -extensions ",
           Ext,
           " -in ",
           ReqFile,
           " -out ",
           CertFile],
    Env = [{"ROOTDIR", RootDir}],
    cmd(Cmd, Env).

-spec generate_host_key(string(), string(), string(), string()) -> atom().
generate_host_key(KeysDir, SSHKeygenCmd, Alg, KeyFile) ->
    io:format("~s: ~s~n", ["HostDir", KeysDir]),
    io:format("~s: ~s~n", ["SSHKeygenCmd", SSHKeygenCmd]),
    io:format("~s: ~s~n", ["Algorithm", Alg]),
    io:format("~s: ~s~n", ["PublicKey", KeyFile ++ ".pub"]),
    io:format("~s: ~s~n", ["PrivateKey", KeyFile]),
    Cmd = ["yes 'y' 2>/dev/null | ", SSHKeygenCmd, " -P ''", " -t ", Alg, " -f ", KeyFile],
    Env = [{"ROOTDIR", KeysDir}],
    cmd(Cmd, Env).

-spec create_dirs(string(), list()) -> ok.
create_dirs(Root, Dirs) ->
    lists:foreach(fun(Dir) ->
                     filelib:ensure_dir(
                         filename:join([Root, Dir])),
                     file:make_dir(
                         filename:join([Root, Dir]))
                  end,
                  Dirs).

-spec create_files(string(), list()) -> ok.
create_files(Root, NameContents) ->
    lists:foreach(fun({Name, Contents}) ->
                     file:write_file(
                         filename:join([Root, Name]), Contents)
                  end,
                  NameContents).

-spec create_rnd(string(), string()) -> atom().
create_rnd(Root, Dir) ->
    From = filename:join([Root, "RAND"]),
    To = filename:join([Root, Dir, "RAND"]),
    file:copy(From, To).

-spec remove_rnd(string(), string()) -> atom().
remove_rnd(Root, Dir) ->
    File = filename:join([Root, Dir, "RAND"]),
    file:delete(File).

-spec cmd(list(), list()) -> atom().
cmd(Cmd, Env) ->
    FCmd = lists:flatten(Cmd),
    io:format("~p~n", [FCmd]),
    io:format("~p~n", [Env]),
    Port = open_port({spawn, FCmd}, [stream, eof, exit_status, {env, Env}]),
    eval_cmd(Port).

-spec eval_cmd(port()) -> atom().
eval_cmd(Port) ->
    receive
        {Port, {data, Data}} ->
            io:format("~p~n", [Data]),
            eval_cmd(Port);
        {Port, eof} ->
            ok
    end,
    receive
        {Port, {exit_status, Status}} when Status /= 0 ->
            io:fwrite("Exit status: ~w~n", [Status])
    after 0 ->
        ok
    end.

-spec openssl_cmd() -> string().
openssl_cmd() ->
    ?OPENSSL.

-spec ssh_keygen_cmd() -> string().
ssh_keygen_cmd() ->
    ?SSH_KEYGEN.

-spec secure_dirname() -> string().
secure_dirname() ->
    ?SECUREDIR.

-spec users_dirname() -> string().
users_dirname() ->
    ?USERSDIR.

%TODO get grid name from configuration
-spec cagrid_dirname() -> string().
cagrid_dirname() ->
    ?CAGRIDDIR.

%TODO get cluster name from configuration
-spec cacluster_dirname() -> string().
cacluster_dirname() ->
    ?CACLUSTERDIR.

%% ============================================================================
%% Contents of configuration files
%% ============================================================================

%openssl x509 -in /opt/swm/spool/secure/users/taras/cert.pem -noout -text
-spec req_cnf(string(), string()) -> list().
req_cnf(DN, Dir) ->
    ["# Purpose: Configuration for requests (end users and CAs).\n"
     "ROOTDIR                = ", Dir, "\n"
     "\n"
     "[req]\n"
     "input_password         = secret\n"
     "output_password        = secret\n"
     "default_bits           = 2048\n"
     "RANDFILE               = $ROOTDIR/RAND\n"
     "encrypt_key            = no\n"
     "default_md             = sha256\n"
     "prompt                 = no\n"
     "distinguished_name     = name\n"
     "\n"
     "[name]\n"
     "commonName             = ", DN#dn.commonName, "\n"
     "organizationalUnitName = ", DN#dn.organizationalUnitName, "\n"
     "organizationName       = ", DN#dn.organizationName, "\n"
     "localityName           = ", DN#dn.localityName, "\n"
     "countryName            = ", DN#dn.countryName, "\n"
     "emailAddress           = ", DN#dn.emailAddress, "\n"
     "subjectAltName         = ", DN#dn.id, "\n"
    ].

-spec ca_cnf(string()) -> list().
ca_cnf(CA) ->
    ["# Purpose: Configuration for CAs.\n\n"
     "ROOTDIR                = $ENV::ROOTDIR\n"
     "default_ca             = ca\n"
     "\n"
     "[ca]\n"
     "dir                    = $ROOTDIR/", CA, "\n"
     "certs                  = $dir/certs\n"
     "crl_dir                = $dir/crl\n"
     "database               = $dir/index.txt\n"
     "new_certs_dir          = $dir/newcerts\n"
     "certificate            = $dir/cert.pem\n"
     "serial                 = $dir/serial\n"
     "crl                    = $dir/crl.pem\n"
     "private_key            = $dir/private/key.pem\n"
     "RANDFILE               = $dir/private/RAND\n"
     "x509_extensions        = user_cert\n"
     "default_days           = 365\n"
     "default_md             = sha256\n"
     "preserve               = no\n"
     "policy                 = policy_match\n"
     "\n"
     "[policy_match]\n"
     "commonName             = supplied\n"
     "organizationalUnitName = optional\n"
     "organizationName       = optional\n"
     "countryName            = optional\n"
     "localityName           = optional\n"
     "emailAddress           = supplied\n"
     "subjectAltName         = supplied\n"
     "\n"
     "[user_cert]\n"
     "basicConstraints       = CA:false\n"
     "keyUsage               = nonRepudiation,digitalSignature,keyEncipherment\n"
     "subjectKeyIdentifier   = hash\n"
     "authorityKeyIdentifier = keyid,issuer:always\n"
     "issuerAltName          = issuer:copy\n"
     "\n"
     "[ca_cert]\n"
     "basicConstraints       = critical,CA:true\n"
     "keyUsage               = cRLSign, keyCertSign\n"
     "subjectKeyIdentifier   = hash\n"
     "issuerAltName          = issuer:copy\n"
    ].

-spec do_get_altname(term()) -> atom() | string().
do_get_altname(Cert) ->
    {rdnSequence, Subject} = Cert#'OTPCertificate'.tbsCertificate#'OTPTBSCertificate'.subject,
    V = [Attribute#'AttributeTypeAndValue'.value
         || [Attribute] <- Subject, Attribute#'AttributeTypeAndValue'.type == ?'id-ce-subjectAltName'],
    case V of
        [Att] ->
            case Att of
                {teletexString, Str} ->
                    Str;
                {printableString, Str} ->
                    Str;
                {utf8String, Bin} ->
                    binary_to_list(Bin);
                _ ->
                    List = binary_to_list(Att),
                    % subjectAltName prefixed with 2 additional bytes, skip them; Erlang OTP bug?
                    lists:sublist(List, 3, length(List))
            end;
        _ ->
            unknown
    end.
