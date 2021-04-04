-module(wm_cert).

-export([create/3, get_uid/1]).

-include_lib("public_key/include/public_key.hrl").

-define(OPENSSL, "openssl").
-define(SSH_KEYGEN, "ssh-keygen").
-define(SECUREDIR, "secure").
-define(NODEDIR, "node").
-define(USERSDIR, "users").
-define(CAGRIDDIR, "grid").
-define(CACLUSTERDIR, "cluster").
-define(ENV_SPOOL, "SWM_SPOOL").
-define(ENV_UNIT, "SWM_UNIT_NAME").
-define(ENV_ORG, "SWM_ORG_NAME").
-define(ENV_LOCALITY, "SWM_LOCALITY").
-define(ENV_COUNTRY, "SWM_COUNTRY").
-define(ENV_EMAIL, "SWM_ADMIN_EMAIL").

-record(dn, {commonName, organizationalUnitName, organizationName, localityName, countryName, emailAddress, id}).

%TODO Put IDs of grid, cluster and node into there CA/certificates

%% ============================================================================
%% API functions
%% ============================================================================

%% @doc Create a root (grid) CA to sign intermediate (cluster) CAs
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

get_uid(Cert) ->
    do_get_altname(Cert).

%% ============================================================================
%% Implementation functions
%% ============================================================================

%% @hidden
create_grid_ca(GridID) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    Request = req_cnf(ask_ca_dn(GridID, cagrid_dirname()), SecureDir),
    ok = filelib:ensure_dir(SecureDir),
    create_rnd(SpoolDir, secure_dirname()),
    create_ca_dir(SecureDir, cagrid_dirname(), ca_cnf(cagrid_dirname())),
    create_self_signed_cert(SecureDir, openssl_cmd(), cagrid_dirname(), Request).

%% @hidden
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

%% @hidden
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

%% @hidden
create_user_cert(UserID, Name) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    create_cert(SpoolDir, Name, UserID, users_dirname()).

%% @hidden
create_host_key(Name) ->
    SpoolDir = ask("Spool directory", ?ENV_SPOOL),
    SecureDir = filename:join([SpoolDir, secure_dirname()]),
    KeysDir = filename:join([SecureDir, Name]),
    RSAKey = filename:join([KeysDir, "ssh_host_rsa_key"]),
    DSAKey = filename:join([KeysDir, "ssh_host_dsa_key"]),
    ECDSAKey = filename:join([KeysDir, "ssh_host_ecdsa_key"]),
    ok = filelib:ensure_dir(KeysDir),
    create_dirs(SecureDir, [Name]),
    generate_host_key(KeysDir, ssh_keygen_cmd(), "rsa", RSAKey),
    generate_host_key(KeysDir, ssh_keygen_cmd(), "dsa", DSAKey),
    generate_host_key(KeysDir, ssh_keygen_cmd(), "ecdsa", ECDSAKey).

%% ============================================================================
%% Auxiliary functions
%% ============================================================================

%% @hidden
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

%% @hidden
ask(Name, DefaultEnv) ->
    case os:getenv(DefaultEnv) of
        X when X == false; X == [] ->
            wm_utils:trail_newline(
                io:get_line(Name ++ ": "));
        Value ->
            Value
    end.

%% @hidden
ask_ca_dn(ID, CommonName) ->
    #dn{commonName = CommonName,
        id = ID,
        organizationalUnitName = ask("Organizational Unit Name", ?ENV_UNIT),
        organizationName = ask("Organization Name", ?ENV_ORG),
        localityName = ask("Locality Name", ?ENV_LOCALITY),
        countryName = ask("Country Name", ?ENV_COUNTRY),
        emailAddress = ask("Email Address", ?ENV_EMAIL)}.

%%@hidden
create_self_signed_cert(SecureDir, OpenSSLCmd, CAName, Cnf) ->
    CADir = filename:join([SecureDir, CAName]),
    CnfFile = filename:join([CADir, "req.cnf"]),
    KeyFile = filename:join([CADir, "private", "key.pem"]),
    CertFile = filename:join([CADir, "cert.pem"]),
    Cmd = [OpenSSLCmd, " req -new -x509 -days 365 -config ", CnfFile, " -keyout ", KeyFile, " -out ", CertFile],
    Env = [{"ROOTDIR", SecureDir}],
    file:write_file(CnfFile, Cnf),
    cmd(Cmd, Env).

%% @hidden
create_ca_dir(KeysRoot, CAName, Cnf) ->
    CADir = filename:join([KeysRoot, CAName]),
    filelib:ensure_dir(KeysRoot),
    filelib:ensure_dir(CADir),
    create_dirs(CADir, ["certs", "crl", "newcerts", "private"]),
    create_rnd(KeysRoot, filename:join([CAName, "private"])),
    create_files(CADir, [{"serial", "01\n"}, {"index.txt", ""}, {"ca.cnf", Cnf}]).

%% @hidden
create_req(ReqDir, OpenSSLCmd, CnfFile, KeyFile, ReqFile) ->
    io:format("~s: ~s~n", ["ReqDir", ReqDir]),
    io:format("~s: ~s~n", ["OpenSSLCmd", OpenSSLCmd]),
    io:format("~s: ~s~n", ["CnfFile", CnfFile]),
    io:format("~s: ~s~n", ["KeyFile", KeyFile]),
    io:format("~s: ~s~n", ["ReqFile", ReqFile]),
    Cmd = [OpenSSLCmd, " req -new -config ", CnfFile, " -keyout ", KeyFile, " -out ", ReqFile],
    Env = [{"ROOTDIR", ReqDir}],
    cmd(Cmd, Env).

%% @hidden
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

%% @hidden
generate_host_key(KeysDir, SSHKeygenCmd, Alg, KeyFile) ->
    io:format("~s: ~s~n", ["HostDir", KeysDir]),
    io:format("~s: ~s~n", ["SSHKeygenCmd", SSHKeygenCmd]),
    io:format("~s: ~s~n", ["Algorithm", Alg]),
    io:format("~s: ~s~n", ["PublicKey", KeyFile ++ ".pub"]),
    io:format("~s: ~s~n", ["PrivateKey", KeyFile]),
    Cmd = ["yes 'y' 2>/dev/null | ", SSHKeygenCmd, " -P ''", " -t ", Alg, " -f ", KeyFile],
    Env = [{"ROOTDIR", KeysDir}],
    cmd(Cmd, Env).

%% @hidden
create_dirs(Root, Dirs) ->
    lists:foreach(fun(Dir) ->
                     filelib:ensure_dir(
                         filename:join([Root, Dir])),
                     file:make_dir(
                         filename:join([Root, Dir]))
                  end,
                  Dirs).

%% @hidden
create_files(Root, NameContents) ->
    lists:foreach(fun({Name, Contents}) ->
                     file:write_file(
                         filename:join([Root, Name]), Contents)
                  end,
                  NameContents).

%% @hidden
create_rnd(Root, Dir) ->
    From = filename:join([Root, "RAND"]),
    To = filename:join([Root, Dir, "RAND"]),
    file:copy(From, To).

%% @hidden
remove_rnd(Root, Dir) ->
    File = filename:join([Root, Dir, "RAND"]),
    file:delete(File).

%% @hidden
cmd(Cmd, Env) ->
    FCmd = lists:flatten(Cmd),
    io:format("~p~n", [FCmd]),
    io:format("~p~n", [Env]),
    Port = open_port({spawn, FCmd}, [stream, eof, exit_status, {env, Env}]),
    eval_cmd(Port).

%% @hidden
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

%% @hidden
openssl_cmd() ->
    ?OPENSSL.

%% @hidden
ssh_keygen_cmd() ->
    ?SSH_KEYGEN.

%% @hidden
secure_dirname() ->
    ?SECUREDIR.

%% @hidden
users_dirname() ->
    ?USERSDIR.

%% @hidden
%TODO get node name from configuration
node_dirname() ->
    ?NODEDIR.

%% @hidden
%TODO get grid name from configuration
cagrid_dirname() ->
    ?CAGRIDDIR.

%% @hidden
%TODO get cluster name from configuration
cacluster_dirname() ->
    ?CACLUSTERDIR.

%% ============================================================================
%% Contents of configuration files
%% ============================================================================

%openssl x509 -in /opt/swm/spool/secure/users/taras/cert.pem -noout -text
%% @hidden
req_cnf(DN, Dir) ->
    ["# Purpose: Configuration for requests "
     "(end users and CAs).\nROOTDIR       "
     "         = ",
     Dir,
     "\n\n[req]\ninput_password         = "
     "secret\noutput_password        = secret\ndefa"
     "ult_bits           = 2048\nRANDFILE "
     "              = $ROOTDIR/RAND\nencrypt_key "
     "           = no\ndefault_md         "
     "    = sha1\nprompt                 = "
     "no\ndistinguished_name     = name\n\n[name]\n"
     "commonName             = ",
     DN#dn.commonName,
     "\norganizationalUnitName = ",
     DN#dn.organizationalUnitName,
     "\norganizationName       = ",
     DN#dn.organizationName,
     "\nlocalityName           = ",
     DN#dn.localityName,
     "\ncountryName            = ",
     DN#dn.countryName,
     "\nemailAddress           = ",
     DN#dn.emailAddress,
     "\nsubjectAltName         = ",
     DN#dn.id,
     "\n"].

%% @hidden
ca_cnf(CA) ->
    ["# Purpose: Configuration for CAs.\n\nROOTDIR "
     "               = $ENV::ROOTDIR\ndefault_ca "
     "            = ca\n\n[ca]\ndir       "
     "             = $ROOTDIR/",
     CA,
     "\ncerts                  = $dir/certs\ncrl_di"
     "r                = $dir/crl\ndatabase "
     "              = $dir/index.txt\nnew_certs_dir "
     "         = $dir/newcerts\ncertificate "
     "           = $dir/cert.pem\nserial  "
     "               = $dir/serial\ncrl   "
     "                 = $dir/crl.pem\nprivate_key "
     "           = $dir/private/key.pem\nRANDFILE "
     "              = $dir/private/RAND\n\nx509_ext"
     "ensions        = user_cert\ndefault_days "
     "          = 365\ndefault_md         "
     "    = sha1\npreserve               = "
     "no\npolicy                 = policy_match\n\n"
     "[policy_match]\ncommonName          "
     "   = supplied\norganizationalUnitName "
     "= optional\norganizationName       = "
     "optional\ncountryName            = optional\n"
     "localityName           = optional\nemailAddre"
     "ss           = supplied\nsubjectAltName "
     "        = supplied\n\n[user_cert]\nbasicConst"
     "raints       = CA:false\nkeyUsage   "
     "            = nonRepudiation,digitalSignature"
     ",keyEncipherment\nsubjectKeyIdentifier "
     "  = hash\nauthorityKeyIdentifier = keyid,issu"
     "er:always\nissuerAltName          = "
     "issuer:copy\n\n[ca_cert]\nbasicConstraints "
     "      = critical,CA:true\nkeyUsage  "
     "             = cRLSign, keyCertSign\nsubjectK"
     "eyIdentifier   = hash\nissuerAltName "
     "         = issuer:copy\n"].

   %"authorityKeyIdentifier = keyid:always,issuer:always\n"

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
                    lists:sublist(List,
                                  3,
                                  length(List)) % subjectAltName prefixed with
                                                % 2 additional bytes, skip them;
                                                % Erlang OTP bug?
            end;
        _ ->
            unknown
    end.
