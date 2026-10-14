# security

This document describes how Sky Port protects the cluster. It covers the
certificate authority (CA), mutual TLS (mTLS), SSH and SFTP, Erlang
distribution (local debugging only), and operator tasks.

Use one trust domain for all components: the cluster CA under `$SWM_SPOOL/secure/`.

## Trust model

Sky Port uses an X.509 hierarchy:

1. **Grid CA** (`secure/grid/`) -- root CA.
2. **Cluster CA** (`secure/cluster/`) -- intermediate CA. Components trust
   `secure/cluster/cert.pem` (and `ca-chain-cert.pem` where a chain is needed).
3. **Node certificate** (`secure/node/`) -- end-entity for this Sky Port node.
4. **User certificates** (`secure/users/<name>/`) -- end-entity for users and clients.

## PKI layout

| Path | Role |
|------|------|
| `secure/grid/` | Root CA |
| `secure/cluster/` | Intermediate CA (`cert.pem`, `private/key.pem`, `ca-chain-cert.pem`) |
| `secure/node/` | Node end-entity (`cert.pem`, `key.pem`) |
| `secure/users/<name>/` | User end-entity certificates |
| `secure/host/` | SSH **host** keys only (`ssh_host_*_key`). Not used for user login. |
| `secure/cookie` | Local Erlang cookie (random per daemon start; mode 0600) |

Keep the cluster CA **private** key on the control plane. Do not share.

### Worker archive

`make worker` / `setup-swm-core.py -a` builds `swm-worker.tar.gz` for job VMs.
That archive must not contain the cluster (or grid) CA private key.

| Included | Not included |
|----------|--------------|
| `secure/cluster/cert.pem`, `ca-chain-cert.pem` | `secure/cluster/private/`, CA ops files (`serial`, `index*`, `newcerts/`, …) |
| `secure/node/{cert,key}.pem` | `secure/grid/` |
| `secure/host/` SSH host keys | `secure/users/` |

Packaging fails if the tarball would contain `secure/cluster/private/` or
`secure/grid/private/`.

Residual risk: job VMs still receive a copy of the Sky Port **node** key so
mesh mTLS works. A job user who can read `/opt` can impersonate that node
identity. Per-VM node certificates (issued on the control plane and injected
outside the shared archive) are a follow-up hardening step.

## Certificate issuance

During setup, Sky Port:

1. Creates the grid CA.
2. Creates the cluster CA and signs it with the grid CA.
3. Creates the node certificate and signs it with the cluster CA.
4. Creates user certificates as needed.
5. Creates SSH host keys under `secure/host/`.

The grid root is self-signed with `basicConstraints CA:TRUE` and
`keyCertSign` / `cRLSign`. OpenSSL 3 rejects chain verification when the root
lacks those CA extensions (verify error 79).

The same CA is used for every component that authenticates with certificates
or with keys derived from those certificates.

## Mutual TLS (mTLS)

These paths use the cluster CA and the node (or user) certificate:

| Path | CA file | Identity |
|------|---------|----------|
| API TCP | `secure/cluster/cert.pem` | `secure/node/{cert,key}.pem` |
| REST (HTTP) | same | same |
| Cloud gate (server) | `secure/cluster/ca-chain-cert.pem` (preferred) or `cert.pem` | Gate serves `secure/node`; **requires** a client cert (`CERT_REQUIRED`) |
| Cloud gate client (Sky Port) | same | `secure/node/{cert,key}.pem` |
| Erlang distribution (`inet_tls`, localhost only) | `ca-chain-cert.pem` | node cert/key |

Clients present a certificate. The server verifies the peer against the cluster
CA. User identity for REST often comes from the peer certificate subject. The
cloud gate rejects TLS handshakes with no client certificate. The gate also
pins the client certificate fingerprint to the node cert when the peer cert is
visible to the ASGI app.

Sky Port (`wm_gate`) must **not** put the node private key in gate HTTP
bodies. Identity to the gate is mTLS only. Azure SP certificate material stays
on the gate (spool or `certificate_path` in `cloud-gate.yaml`).

Cluster control plane traffic uses the API (`wm_rpc` over mTLS). It does not
use Erlang distribution between hosts.

Peer ETF (API TCP, SSH SFTP EXT, Porter stdout, scheduler port output) is
decoded with `binary_to_term(..., [safe])` and a size limit (default 16 MiB).
That blocks atom-table exhaustion from crafted terms. Application validation
of decoded terms remains required.

### RPC authorization

After mTLS, `wm_session` checks the peer certificate UID and allows only:

| Peer role | How classified | Allowed RPC targets |
|-----------|----------------|---------------------|
| `node` | UID in the node table, or matches `$SWM_SPOOL/secure/node/cert.pem` | Mesh modules (`wm_compute`, `wm_conf`, `wm_db`, `wm_pinger`, factories, and related) |
| `admin` | User with `acl` containing `admin`, or name equals `SWM_ADMIN_USER`, or bootstrap match under `secure/users/*/cert.pem` before the user row exists | `wm_admin` only (`swmctl`) |
| `user` | Other user UIDs | None (use the REST `/user` API) |
| `unknown` | No match | None |

Default is deny. Unknown modules return `{error, forbidden}`.

Grant RPC admin to an operator:

```bash
swmctl user <name> set acl admin
```

Setup sets `acl=admin` for `SWM_ADMIN_USER` when it creates that user.

### REST job ownership

Job routes under `/user/job` require a registered peer certificate. The server
maps the cert UID to a user row, then compares that user id with `job.user_id`.

| Result | HTTP |
|--------|------|
| Missing or unknown cert | 401 |
| Job exists, other owner | 403 (no job payload) |
| Job missing | 404 |
| Owner match | Proceed (show, stdout, stderr, metrics, cancel, requeue) |

`GET /user/job` (list) returns only jobs for the caller. Catalog GETs
(`/user/node`, flavor, image, remote) stay unrestricted. Submit and purge still
resolve the username from the cert (unchanged status codes for those paths).

### REST job submit body

`POST /user/job` accepts the job script only in the request body (plain or
multipart). The `path` query parameter is rejected with HTTP 400. The server
must not read job scripts from the host filesystem on behalf of the client.

`#SWM account` must name an account where the submitter is in `users` or
`admins`. Other accounts and unknown names are rejected at submit.

`#SWM submission-address` may only name localhost / this host, the submit peer
IP, or an entry in `submission_address_allowlist`. That blocks using port
forwarding as a TCP relay to arbitrary hosts.

## Logging

Do not write secrets or full payloads to logs:

- Erlang cookie value (`SWM_COOKIE` / `$SWM_SPOOL/secure/cookie`)
- SSH passwords or other credentials
- Full job scripts or HTTP request/response bodies
- Full Cowboy `Req` maps (they include the peer certificate)

Prefer method, path, status, sizes, and allowlisted headers. Use
`wm_log_safe` helpers for HTTP body and header summaries.

Before you add a `?LOG_*` near credentials or HTTP:

1. Check whether the message can hold a script, body, password, or cookie.
2. Log identifiers and sizes instead of content.
3. Keep returned error bodies for callers; change only what is logged.

## Erlang distribution (local debugging only)

Erlang distribution is enabled only so operators can attach locally with
`remsh`, `etop`, or `observer`, and so `run-in-shell.sh -s` can stop the node
via `rpc:call`.

Constraints:

1. **Listen on localhost only.** `inet_dist_use_interface` is `{127,0,0,1}` and
   `ERL_EPMD_ADDRESS=127.0.0.1`. Remote hosts cannot open a distribution
   channel. SSH to the host first, then remsh.
2. **Random cookie per daemon start.** On start, Sky Port writes
   `$SWM_SPOOL/secure/cookie` (mode 0600) and passes it to `-setcookie`. The
   cookie is not shared across nodes and is not packed into the worker archive.
   Local tools load that file; they do not invent a cookie. Never log the
   cookie value.
3. **Dist TLS peer verify.** Server and client use `verify_peer`; the server
   sets `fail_if_no_peer_cert`. Remsh clients must present the node certificate.
   Node certs need a DNS SAN for `sname@fqdn` (see cert issuance).
4. **Hostname for remsh.** With `-name node@FQDN`, the client connects to the
   IP of `FQDN`. That name must resolve to loopback on the host (for example
   via `/etc/hosts`), or remsh fails even from the same machine.

Health checks use `scripts/swm-ping` (API / `wm_pinger`), not `net_adm:ping`.

File transfer uses SFTP only. There is no Erlang-distribution file transport.

## SSH and SFTP

Sky Port runs two OTP SSH daemons inside the BEAM process:

| Daemon | Default port | Purpose |
|--------|--------------|---------|
| Tunnel (`wm_ssh_server`) | `10022` | TCP forwarding |
| File transfer (`wm_file_transfer`) | `31337` | SFTP and extensions |

### Authentication

- Use **public-key** authentication only. Password login is off.
- The client uses the CA-issued **node** private key (`secure/node/key.pem`).
- The server accepts a key only if it matches the node certificate and that
  certificate validates against `secure/cluster/cert.pem`.
- Interactive shell and remote `exec` are disabled.
- `secure/host/` holds SSH host keys for the daemon identity. It does not hold
  user login keys.

### Host key verification

SWM pubkey SSH clients do **not** silently accept hosts. `wm_ssh_key_cb`
accepts a server host key only when it matches:

1. A public key under `$SWM_SPOOL/secure/host/ssh_host_*.pub` (pinned; the
   worker archive ships the same host keys to job VMs), or
2. An entry in `$SWM_SPOOL/secure/host/known_hosts` (OpenSSH format).

Provisioning password SSH to cloud OpenSSH may still trust-on-first-use into
the caller's `user_dir/known_hosts` (separate from the SWM pin).

### Certificate profiles

End-entity certificates carry distinct `extendedKeyUsage` profiles:

| Profile | Path | EKU |
|---------|------|-----|
| `node` | `secure/node/` | `serverAuth` + `clientAuth` |
| `user` | `secure/users/<name>/` | `clientAuth` only |

EKU (Extended Key Usage) is not marked critical. OTP `public_key:pkix_path_validation/3` rejects
unknown critical extensions, which would break SSH node-key auth.

RPC classification (`wm_rpc_acl:classify_peer/1`) rejects a **user** profile
certificate when the UID would otherwise map to the `node` role. Legacy
certificates without EKU keep UID-based classification until re-issued.

OTP SSH does not accept X.509 PEM files as native SSH user certificates. Sky
Port maps the same CA-issued node key material into SSH public-key auth so the
trust domain stays the cluster CA.

### Listen address

Global `ssh_daemon_listen_ip` parameter sets the bind address for both daemons.
The default is `127.0.0.1` (local Sky Port / development).

Cloud **job main** nodes must listen on `0.0.0.0` (or the public NIC). Sky Port
opens the SSH tunnel to the VM public IP on port `10022`; that tunnel exposes
`localhost:10002` on the VM so the job main can reach its parent. A loopback
bind causes `econnrefused` on Sky Port and leaves cloud nodes non-IDLE.

`setup-swm-core.py --job-node main|compute` sets `ssh_daemon_listen_ip` to
`0.0.0.0` automatically. Do not set job nodes back to `127.0.0.1`.

### SFTP root

The file-transfer SFTP allowlist is per connection:

1. The **authenticated user's home directory** (`pw_dir`).
2. **`$SWM_SPOOL/job/`** (job stdout/stderr and related logs).

Clients cannot read or write other paths through SFTP (including
`$SWM_SPOOL/secure/`). The custom SFTP extension applies the same limit.

Job workdirs must stay under the job owner's home (default `$HOME`). The
server rejects workdirs with shell metacharacters, `..` segments, or paths
outside the owner's home. Container finalize runs the finalize script with an
argv list (no `/bin/sh -c`), so the workdir cannot inject shell commands.
Job `stdout*` / `stderr*` files default to `$SWM_SPOOL/job/<job-id>/`.

### Porter job script and control socket

Porter writes the job script under `$SWM_SPOOL/job/<job-id>/` with
`O_CREAT|O_EXCL|O_NOFOLLOW` (mode `0700`). If `SWM_SPOOL` is unset,
Porter uses a private `mkdtemp` directory.

Before the job starts, Porter calls `initgroups` for the job user, then
drops uid and gid. Jobs do not keep root's supplementary groups.

The Porter control socket for `swm-task` is
`$SWM_SPOOL/job/<job-id>/ctrl.sock` (mode `0600`, owned by the job user).

### PMIx server tmpdir

`swm-pmix` sets `PMIX_SERVER_TMPDIR` to `$SWM_SPOOL/job/<job-id>/pmix`
(mode `0700`) by default. Override with `SWM_PMIX_TMPDIR` when needed.
World-writable GDS (`chmod -R a+rwX`) is off unless you set `SWM_PMIX_WORLD_TMP=1`.

### OpenSSH provisioning

Cloud VM provisioning still uses host OpenSSH on the provision port (default 22).
That path is separate from the SWM OTP SSH daemons.

## Operator tasks

### Set the SSH listen address

1. Set global `ssh_daemon_listen_ip`:
   - Local Sky Port: `127.0.0.1`
   - Cloud job nodes: `0.0.0.0` (required for Sky Port tunnels)
2. Restart Sky Port.
3. Check listeners (they must match the configured address):

```bash
ss -lntp | grep -E '10022|31337'
```

### Check local distribution bind

```bash
ss -lntp | grep -E '4369|5000[0-9]'
```

Listeners for epmd and the dist port range must show `127.0.0.1` (not `0.0.0.0`).

### Rotate certificates

1. Create new certificates with the setup / `wm_cert` flow.
2. Install them under `$SWM_SPOOL/secure/` with the same layout.
3. Restart Sky Port and clients that load user certificates (for example under `~/.swm/`).

## Related documents

- [INSTALL.md](INSTALL.md) -- install and setup
- [CONTAINERS.md](CONTAINERS.md) -- job containers
- [JOBS.md](JOBS.md) -- job submission
