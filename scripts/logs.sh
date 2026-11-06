#!/usr/bin/env bash
# Follows logs for every service, or only the ones named.
#
# Usage: npm run logs [-- service...]
#   e.g. npm run logs -- apha-risk-insights-backend mongodb

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

require_docker
compose logs --follow --tail 100 "$@"
