#!/usr/bin/env bash
# Stops every service.
#
# Usage: npm run stop  (or npm run stop:clean)
#   --clean  also delete volumes (wipes local MongoDB data)

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

down_args=(down --remove-orphans)
for arg in "$@"; do
  case "$arg" in
    --clean) down_args+=(--volumes) ;;
    -h | --help)
      sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown option: $arg" ;;
  esac
done

require_docker
info "Stopping services"
compose "${down_args[@]}"
ok "Stopped"
