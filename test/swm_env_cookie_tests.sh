#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © 2026 Taras Shapovalov
# SPDX-License-Identifier: BSD-3-Clause
#
# Unit checks for per-start local cookie handling in scripts/swm.env
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [ "${expected}" = "${actual}" ]; then
    echo "PASS: ${name}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${name} (expected=${expected} actual=${actual})"
    FAIL=$((FAIL + 1))
  fi
}

assert_ok() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS: ${name}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${name}"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: ${name} (expected non-zero exit)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: ${name}"
    PASS=$((PASS + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

export SWM_ROOT="${TMP}/root"
export SWM_SPOOL="${TMP}/spool"
mkdir -p "${SWM_ROOT}" "${SWM_SPOOL}"
# Dev tree detection: ROOT_DIR of swm.env is repo root; force release-like paths
# by pointing version dir equal to a fake install and sourcing carefully.

# Missing cookie without optional/regenerate -> fail
assert_fail "missing cookie fails" \
  env -u SWM_COOKIE -u SWM_REGENERATE_COOKIE -u SWM_COOKIE_OPTIONAL \
  bash -c "source '${ROOT_DIR}/scripts/swm.env'"

# Optional -> success without cookie file
assert_ok "optional allows missing cookie" \
  env -u SWM_COOKIE -u SWM_REGENERATE_COOKIE SWM_COOKIE_OPTIONAL=1 \
  bash -c "source '${ROOT_DIR}/scripts/swm.env'"

# Regenerate creates 0600 cookie, exports SWM_COOKIE, installs ~/.erlang.cookie
OUT=$(env -u SWM_COOKIE SWM_REGENERATE_COOKIE=1 SWM_COOKIE_OPTIONAL=0 HOME="${TMP}/home" \
  bash -c "mkdir -p \"\${HOME}\"; source '${ROOT_DIR}/scripts/swm.env' >/dev/null; echo \"\${SWM_COOKIE}\"; stat -c '%a' \"\${SWM_COOKIE_FILE}\"; stat -c '%a' \"\${HOME}/.erlang.cookie\"; tr -d '\\n' < \"\${HOME}/.erlang.cookie\"")
COOKIE1=$(echo "${OUT}" | sed -n '1p')
MODE=$(echo "${OUT}" | sed -n '2p')
HOME_MODE=$(echo "${OUT}" | sed -n '3p')
HOME_COOKIE=$(echo "${OUT}" | sed -n '4p')
assert_eq "cookie mode 0600" "600" "${MODE}"
assert_eq "HOME .erlang.cookie mode 0600" "600" "${HOME_MODE}"
assert_eq "HOME .erlang.cookie matches spool" "${COOKIE1}" "${HOME_COOKIE}"
if [ "${#COOKIE1}" -ge 32 ]; then
  echo "PASS: cookie length"
  PASS=$((PASS + 1))
else
  echo "FAIL: cookie length (${#COOKIE1})"
  FAIL=$((FAIL + 1))
fi

# Load existing cookie (no regenerate) keeps the same value
COOKIE2=$(env -u SWM_COOKIE -u SWM_REGENERATE_COOKIE HOME="${TMP}/home" \
  bash -c "source '${ROOT_DIR}/scripts/swm.env' >/dev/null; echo \"\${SWM_COOKIE}\"")
assert_eq "load existing cookie" "${COOKIE1}" "${COOKIE2}"

# Regenerate replaces cookie
COOKIE3=$(env -u SWM_COOKIE SWM_REGENERATE_COOKIE=1 HOME="${TMP}/home" \
  bash -c "source '${ROOT_DIR}/scripts/swm.env' >/dev/null; echo \"\${SWM_COOKIE}\"")
if [ "${COOKIE1}" != "${COOKIE3}" ] && [ "${#COOKIE3}" -ge 32 ]; then
  echo "PASS: regenerate replaces cookie"
  PASS=$((PASS + 1))
else
  echo "FAIL: regenerate replaces cookie"
  FAIL=$((FAIL + 1))
fi

# No SWM_COOKIE in env dump
DUMP=$(env -u SWM_COOKIE SWM_REGENERATE_COOKIE=1 HOME="${TMP}/home" \
  bash -c "source '${ROOT_DIR}/scripts/swm.env'" | grep '^SWM_COOKIE=' || true)
assert_eq "cookie not printed by swm.env" "" "${DUMP}"

# Cookie must not appear as -setcookie in vm.args template
assert_fail "vm.args.src has no -setcookie" \
  grep -qE '^-setcookie' "${ROOT_DIR}/config/vm.args.src"

# Dist TLS via ssl_dist_optfile (verify_peer + node verify_fun live in the optfile)
assert_ok "vm.args.src ssl_dist_optfile" \
  grep -qE '^-ssl_dist_optfile[[:space:]]+' "${ROOT_DIR}/config/vm.args.src"

# Regenerating cookie also writes a 0600 ssl dist optfile with verify_fun
OPT_OUT=$(env -u SWM_COOKIE SWM_REGENERATE_COOKIE=1 HOME="${TMP}/home" \
  bash -c "source '${ROOT_DIR}/scripts/swm.env' >/dev/null; echo \"\${SWM_SSL_DIST_OPTFILE}\"; stat -c '%a' \"\${SWM_SSL_DIST_OPTFILE}\"")
OPT_FILE=$(echo "${OPT_OUT}" | sed -n '1p')
OPT_MODE=$(echo "${OPT_OUT}" | sed -n '2p')
assert_eq "ssl_dist_optfile mode 0600" "600" "${OPT_MODE}"
assert_ok "ssl_dist_optfile has verify_fun" \
  grep -q 'wm_ssl_dist' "${OPT_FILE}"
assert_ok "ssl_dist_optfile has verify_peer" \
  grep -q 'verify_peer' "${OPT_FILE}"

# systemd unit sets UMask so release files are not world-readable
assert_ok "systemd UMask=0077" \
  grep -qE '^UMask=0077$' "${ROOT_DIR}/priv/setup/systemd-service.linux"

# sys.config.src binds dist to loopback
assert_ok "sys.config.src inet_dist_use_interface" \
  grep -q '{inet_dist_use_interface, {127,0,0,1}}' "${ROOT_DIR}/config/sys.config.src"

echo
echo "Passed: ${PASS}  Failed: ${FAIL}"
[ "${FAIL}" -eq 0 ]
