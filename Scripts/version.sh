#!/bin/bash
# Resolve the MeiPDF version.
# Priority: $MEIPDF_VERSION env -> latest git tag (stripped of leading 'v') -> 1.0.0
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
  echo "1.0.11"
}
