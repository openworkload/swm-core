# Security

This document describes how Sky Port protects the cluster. It covers the
certificate authority (CA), mutual TLS (mTLS), SSH and SFTP, and operator
tasks.

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
| Erlang distribution (`inet_tls`) | `ca-chain-cert.pem` | node cert/key |

Clients present a certificate. The server verifies the peer against the cluster
CA. User identity for REST often comes from the peer certificate subject.

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

- Default Erlang cookie and distribution TLS peer checks.
- RPC permission allowlists.
- REST job owner checks.
- Job submit path that reads server files.
- Worker archive contents (cluster CA private key).
- Gate client-certificate requirements.
- Other connectors and frontends listed in the security plan.

Update this document when those gaps close.

## Related documents

- [INSTALL.md](INSTALL.md) -- install and setup
- [CONTAINERS.md](CONTAINERS.md) -- job containers
- [JOBS.md](JOBS.md) -- job submission
