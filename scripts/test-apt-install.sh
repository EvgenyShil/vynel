#!/usr/bin/env bash
# Exercise package recovery with fake APT commands, without root or network access.
set -euo pipefail
cd "$(dirname "$0")/.."
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

# Only function definitions; never execute the installer's top level.
eval "$(sed -n '/^apt_update() {/,/^# What the installation needs/p' scripts/install.sh)"

for scenario in installed fresh cached-download fresh-404 stale update-failed download-failed ipv4; do
  (
    APT_LOG="$test_root/$scenario.log"
    events="$test_root/$scenario.events"
    APT_OPTS=(-o DPkg::Lock::Timeout=600)
    refreshed=0
    : >"$APT_LOG"
    : >"$events"
    info() { :; }
    red() { :; }
    wait_apt_idle() { :; }
    dpkg() { :; }
    dpkg-query() { [[ "$scenario" == installed ]] && echo 'install ok installed'; }
    lists_fresh() { [[ "$scenario" == fresh* || "$scenario" == cached-download || "$scenario" == download-failed ]]; }
    run_step() { shift 3; "$@" >>"$APT_LOG" 2>&1; }
    apt-get() {
      local args=" $* "
      [[ "$args" == *' DPkg::Lock::Timeout=600 '* ]] || return 99
      if [[ "$args" == *' update '* ]]; then
        echo update >>"$events"
        if [[ "$scenario" == ipv4 && "$args" != *' Acquire::ForceIPv4=true '* ]]; then
          return 124
        fi
        if [[ "$scenario" == update-failed ]]; then
          echo 'W: Some index files failed to download. They have been ignored, or old ones used instead.'
          [[ "$args" != *' APT::Update::Error-Mode=any '* ]]
          return
        fi
        if [[ "$args" == *' Acquire::http::No-Cache=true '* && "$args" == *' Acquire::https::No-Cache=true '* ]]; then
          refreshed=1
        fi
      elif [[ "$args" == *' --download-only '* ]]; then
        echo download >>"$events"
        if [[ "$scenario" == cached-download && ( "$args" != *' Acquire::http::No-Cache=true '* || "$args" != *' Acquire::https::No-Cache=true '* ) ]]; then
          echo 'E: Failed to fetch nginx.deb 404 Not Found (cached response)'
          return 100
        fi
        if [[ "$scenario" == download-failed || ( "$scenario" != fresh && "$scenario" != cached-download && $refreshed -eq 0 ) ]]; then
          echo 'E: Failed to fetch nginx.deb 404 Not Found'
          return 100
        fi
      else
        echo install >>"$events"
      fi
      return 0
    }

    rc=0
    try_packages nginx libnginx-mod-stream >/dev/null || rc=$?
    case "$scenario" in
      installed) expected=""; expected_rc=0 ;;
      fresh|cached-download) expected=$'download\ninstall'; expected_rc=0 ;;
      fresh-404) expected=$'download\nupdate\ndownload\ninstall'; expected_rc=0 ;;
      stale) expected=$'update\ndownload\ninstall'; expected_rc=0 ;;
      update-failed) expected=update; expected_rc=1 ;;
      download-failed) expected=$'download\nupdate\ndownload'; expected_rc=1 ;;
      ipv4) expected=$'update\nupdate\ndownload\ninstall'; expected_rc=0 ;;
    esac
    if [[ $rc -ne $expected_rc || "$(cat "$events")" != "$expected" ]]; then
      echo "FAIL: $scenario returned $rc (expected $expected_rc); APT calls:" >&2
      cat "$events" "$APT_LOG" >&2
      exit 1
    fi
  )
done
echo 'APT installer checks passed'
