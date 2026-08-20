#!/bin/bash
# Resolve the MeiPDF version.
# Priority: $MEIPDF_VERSION env -> latest git tag (stripped of leading 'v')
#           -> Resources/Info.plist (single source of truth) -> 1.0.0
resolve_version() {
  if [ -n "${MEIPDF_VERSION:-}" ]; then
    echo "$MEIPDF_VERSION"
    return
  fi
  local v
  v=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$v" ]; then
    echo "${v#v}"
    return
  fi
  local plist
  plist="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Resources/Info.plist"
  if [ -f "$plist" ]; then
    v=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || true)
    [ -n "$v" ] && { echo "$v"; return; }
  fi
  echo "1.0.0"
}
