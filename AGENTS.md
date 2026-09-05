# Agent instructions — swm-core

Guidance for coding agents working on this repository. The codebase is primarily **Erlang/OTP** (rebar3) with **C++** in `c_src/` (Porter and shared libraries).

## Stack and layout

- **Erlang**: application under `src/`, headers in `include/`, `rebar.config` defines OTP **27+** (`{minimum_otp_vsn, "27"}`).
- **C++**: `c_src/porter/` (Porter binary), `c_src/lib/` (shared code), built via nested Makefiles; `make porter` from the repo root.
- **Tests**: EUnit and Common Test live under `test/` (`*_SUITE.erl` for CT). rebar3 is `./rebar3` at the repo root.

## Build (typical)

- `make gen` — regenerate cog outputs where applicable.
- `make format` — format generated and source files after `make gen`.
- `make porter` — build C++ Porter.
- `make compile` — `./rebar3 compile`.

Prefer existing Makefile and rebar3 targets over ad hoc commands.

## Tests

Local CI via [nektos/act](https://github.com/nektos/act) (installed in the debug
container). Repo `.actrc` sets `--network bridge` so the job does not share the
host port namespace with `skyport-dev`'s published `10001` mapping.

* Run Erlang unit tests:
act --job unit_tests

* Run Erlang common tests:
act --job common_tests

## Dev container (`make cr`)

To get Erlang environment for the project use `make cr` command to spawn an interactive session in the container, then inside the shell `cd` to this repository if needed.

- Image: `swm-build:27.3` (see `priv/container/debug/Dockerfile` and `scripts/build-debug-container.sh`).
- Container name: **`skyport-dev`**.
- `make cr` runs `scripts/start-debug-container.sh`: attaches with  
  `docker exec -ti skyport-dev runuser -u <host-user> /bin/bash`  
  (same `$HOME` mount as on the host, workdir is usually the directory from which the container was first created).

## Erlang + C++ conventions for agents

- **Erlang**: follow existing module layout, types/specs where the file already uses them, rebar3 profiles, and `make format` / lint expectations already wired in the repo.
- **C++**: match style and patterns in `c_src/lib/` and `c_src/porter/`; build through **`make porter`** or the subdirectory Makefiles rather than inventing new build systems.
- **Scope**: change only what the task requires; do not refactor unrelated Erlang or C++ without a clear need.

## Release note

`make release` / relx may expect sibling artifacts (e.g. `../swm-sched` binaries per `rebar.config`). If release or CT prep fails on missing paths, check CI and local sibling repos.
