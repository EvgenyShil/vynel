#!/usr/bin/env bash
# Kept for old links: the installer is scripts/install.sh now (menu: all-in-one, panel, node,
# update, uninstall). Flags are passed through; --domain alone still means all-in-one.
set -euo pipefail
here=""
if here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P); then
  :
fi
if [[ -n "$here" && -f "$here/install.sh" ]]; then
  exec bash "$here/install.sh" "$@"
fi
# The installer comes from a release (edge-main by default; VYNEL_RELEASE overrides the tag).
RELEASE="${VYNEL_RELEASE:-edge-main}"
if [[ "$RELEASE" == latest ]]; then
  url="https://github.com/EvgenyShil/vynel/releases/latest/download/install.sh"
else
  url="https://github.com/EvgenyShil/vynel/releases/download/$RELEASE/install.sh"
fi
exec bash <(curl -fsSL "$url") "$@"
