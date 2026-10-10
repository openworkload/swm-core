# Security

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

## Certificate issuance

During setup, Sky Port:

1. Creates the grid CA.
2. Creates the cluster CA and signs it with the grid CA.
3. Creates the node certificate and signs it with the cluster CA.
4. Creates user certificates as needed.
5. Creates SSH host keys under `secure/host/`.

The same CA is used for every component that authenticates with certificates
or with keys derived from those certificates.

## Mutual TLS (mTLS)

These paths use the cluster CA and the node (or user) certificate:

| Path | CA file | Identity |
|------|---------|----------|
| API TCP | `secure/cluster/cert.pem` | `secure/node/{cert,key}.pem` |
| REST (HTTP) | same | same |
| Cloud gate client | same | same |
| Erlang distribution (`inet_tls`, localhost only) | `ca-chain-cert.pem` | node cert/key |

Clients present a certificate. The server verifies the peer against the cluster
CA. User identity for REST often comes from the peer certificate subject.

Cluster control plane traffic uses the API (`wm_rpc` over mTLS). It does not
use Erlang distribution between hosts.

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
   Local tools load that file; they do not invent a cookie.
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

Job workdirs must stay under the job owner's home (default `$HOME`). Job
`stdout*` / `stderr*` files default to `$SWM_SPOOL/job/<job-id>/`.

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

### Service user

The systemd unit may still run as root because privileged helpers (for example
container control) need access. SSH ports themselves do not need root. Plan a
non-root service user when those helpers are scoped.

## Known gaps

These items are tracked in the security fix plan and may still need work:

- Job submit path that reads server files.
- Worker archive contents (cluster CA private key).
- Gate client-certificate requirements.
- Other connectors and frontends listed in the security plan.

Update this document when those gaps close.

## Related documents

- [INSTALL.md](INSTALL.md) -- install and setup
- [CONTAINERS.md](CONTAINERS.md) -- job containers
- [JOBS.md](JOBS.md) -- job submission
