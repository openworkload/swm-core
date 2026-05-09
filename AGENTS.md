# Agent instructions — swm-core

Guidance for coding agents working on this repository. The codebase is primarily **Erlang/OTP** (rebar3) with **C++** in `c_src/` (Porter and shared libraries).

## Stack and layout

- **Erlang**: application under `src/`, headers in `include/`, `rebar.config` defines OTP **27+** (`{minimum_otp_vsn, "27"}`).
- **C++**: `c_src/porter/` (Porter binary), `c_src/lib/` (shared code), built via nested Makefiles; `make porter` from the repo root.
- **Tests**: EUnit and Common Test live under `test/` (`*_SUITE.erl` for CT). rebar3 is `./rebar3` at the repo root.

## Build (typical)

- `make gen` — regenerate cog outputs where applicable.
- `make porter` — build C++ Porter.
- `make compile` — `./rebar3 compile`.

Prefer existing Makefile and rebar3 targets over ad hoc commands.

## Tests (Makefile)

| Target        | What it runs                                      |
|---------------|---------------------------------------------------|
| `make test_unit` | `./rebar3 eunit skip_deps=true`                |
| `make test_ct`   | `./rebar3 ct --dir test --verbose`             |
| `make test`      | sources `scripts/swm.env`, then eunit then CT  |
| `make ftest`     | shell-based functional tests (`test/test-all.sh`) |

Run tests **inside the OTP 27 dev environment** (see below). Host OTP versions older than the bundled rebar3 BEAMs will fail to start rebar3.

## Dev container (`make cr`)

- Image: `swm-build:27.3` (see `priv/container/debug/Dockerfile` and `scripts/build-debug-container.sh`).
- Container name: **`skyport-dev`**.
- `make cr` runs `scripts/start-debug-container.sh`: attaches with  
  `docker exec -ti skyport-dev runuser -u <host-user> /bin/bash`  
  (same `$HOME` mount as on the host, workdir is usually the directory from which the container was first created).

For **manual** work: from the repo root, run `make cr`, then inside the shell `cd` to this repository if needed and run `make test_ct` (or `make test_unit`).

## Running CT tests from an agent (non-interactive)

`make cr` is interactive (`-ti`). To run **the same shell environment** without a human TTY, use **`docker exec`** with the same user the script uses:

```bash
docker exec skyport-dev runuser -u "$(id -un)" -- bash -lc 'cd /absolute/path/to/swm-core && make test_ct'
```

Replace `/absolute/path/to/swm-core` with the real checkout path (must match the bind-mounted tree, e.g. under your home directory).

If you must drive **`make cr` itself** (pseudo-TTY for `docker exec -ti`), you can wrap it:

```bash
cd /absolute/path/to/swm-core
script -qec 'make cr' /dev/null <<'EOF'
cd /absolute/path/to/swm-core
make test_ct
exit
EOF
```

The `docker exec … bash -lc '… make test_ct'` form is simpler for automation and matches how the dev container is entered in practice.

## CT expectations (environment)

Common Test suites talk to **swm-cloud-gate** (mock) and TLS material. If CT fails with missing files (`enoent` in PEM paths) or gate errors:

- Align with **`.github/workflows/ci.yml`**: optional Python build, `make compile` / `make release`, clone and venv **`swm-cloud-gate`**, **`SWM_GATE_DIR`** pointing at that checkout, and **`./scripts/setup-skyport-dev.sh`** for dev keys where applicable.
- `test/wm_ct_helpers.erl` resolves the gate directory from **`SWM_GATE_DIR`** or a default path relative to the test build.

## Erlang + C++ conventions for agents

- **Erlang**: follow existing module layout, types/specs where the file already uses them, rebar3 profiles, and `make format` / lint expectations already wired in the repo.
- **C++**: match style and patterns in `c_src/lib/` and `c_src/porter/`; build through **`make porter`** or the subdirectory Makefiles rather than inventing new build systems.
- **Scope**: change only what the task requires; do not refactor unrelated Erlang or C++ without a clear need.

## Release note

`make release` / relx may expect sibling artifacts (e.g. `../swm-sched` binaries per `rebar.config`). If release or CT prep fails on missing paths, check CI and local sibling repos.
