# Agent instructions — swm-core

Guidance for coding agents working on this repository. The codebase is primarily **Erlang/OTP** (rebar3) with **C++** in `c_src/` (Porter and shared libraries).

## Stack and layout

- **Erlang**: application under `src/`, headers in `include/`, `rebar.config` defines OTP **29+** (`{minimum_otp_vsn, "29"}`).
- **C++**: `c_src/porter/` (Porter binary), `c_src/lib/` (shared code), built via nested Makefiles; `make porter` from the repo root.
- **Tests**: EUnit and Common Test live under `test/` (`*_SUITE.erl` for CT). rebar3 is `./rebar3` at the repo root.

## Build (typical)

- `make gen` -- regenerate cog outputs; also runs `scripts/format-cpp.sh` on `c_src/`.
- `make format` -- format Erlang (`rebar3 format`) and C++ under `c_src/` (`scripts/format-cpp.sh`, `.clang-format`).
- `make porter` — build C++ Porter.
- `make compile` — `./rebar3 compile`.
- `make build-all` — full build in `skyport-dev` as `$USER`; **stops SWM first** so sync cannot race `rebar3`/compile.

Prefer existing Makefile and rebar3 targets over ad hoc commands.

## Tests

Local CI via [nektos/act](https://github.com/nektos/act) against the host
**Podman** Docker-compatible API (`make act` → `scripts/run-act.sh`). Requires
`podman.socket` (or `podman system service`) so
`$XDG_RUNTIME_DIR/podman/podman.sock` exists. Repo `.actrc` sets
`--network bridge` so the job does not share the host port namespace with
`skyport-dev`'s published `10001` mapping.

* Run all CI jobs locally:
make act

* Run Erlang unit tests:
make act ARGS='--job unit_tests'

* Run Erlang common tests:
make act ARGS='--job common_tests'

## Dev container (`make cr`)

To get Erlang environment for the project use `make cr` command to spawn an interactive session in the container, then inside the shell `cd` to this repository if needed.

- Image: `swm-build:29.1` (see `priv/container/debug/Containerfile` and `scripts/build-debug-container.sh`).
- Container name: **`skyport-dev`** (Podman).
- `make cr` runs `scripts/start-debug-container.sh`: attaches with  
  `podman exec -ti --user <host-user> skyport-dev /bin/bash`  
  (same `$HOME` mount as on the host, workdir is usually the directory from which the container was first created). Containers use `--userns=keep-id` (no `runuser`).
- Passwordless `sudo` is set up on `make cr` (interactive shell only). Host
  `/etc/shadow` is **not** bind-mounted (unreadable under keep-id and breaks sudo).
  If an older container still mounts it, recreate: `podman rm -f skyport-dev && make cr`.
- First `podman run --userns=keep-id` of the multi-GB `swm-build` image can take
  several minutes (ID-mapped layer copy). Do not interrupt it.

### Agents: never compile as root

Always match `make cr` / `scripts/run-in-dev-container.sh` and run as the host user so build artifacts stay owned by that user:

```bash
podman exec --user "$USER" skyport-dev bash -lc '
  source /usr/erlang/activate
  export REBAR_CACHE_DIR="${HOME}/.cache/rebar3"
  mkdir -p "${REBAR_CACHE_DIR}"
  cd /path/to/swm-core && make compile
'
```

Use the host `$USER` (or the uid that owns the workspace). Do not use bare `podman exec` without `--user` for `make compile`, `./rebar3`, `make gen`, `make format`, or `make porter`.

## Erlang + C++ conventions for agents

- **Erlang**: follow existing module layout, types/specs where the file already uses them, rebar3 profiles, and `make format` / lint expectations already wired in the repo.
- **No Unicode em-dash (`—`, U+2014) in source or log strings.** `wm_log` formats messages with `~s`, which rejects codepoints above 255 and can crash the caller (e.g. `wm_factory`). Use ASCII `--` (or plain hyphen) instead. Prefer ASCII-only in `?LOG_*` format strings generally.
- **After plan execution (or any non-trivial Erlang change):** force a clean recompile of touched modules and **fix all new Erlang warnings** (`warn_missing_spec`, unused variables, deprecated `catch ...`, etc.). Do not leave the work with warnings introduced by the change. Do `make compile` and inspect compiler output for the modules you edited.
- **C++**: match style and patterns in `c_src/lib/` and `c_src/porter/`; build through **`make porter`** or the subdirectory Makefiles rather than inventing new build systems.
- **Scope**: change only what the task requires; do not refactor unrelated Erlang or C++ without a clear need.

## Release note

`make release` / relx may expect sibling artifacts (e.g. `../swm-sched` binaries per `rebar.config`). If release or CT prep fails on missing paths, check CI and local sibling repos.
