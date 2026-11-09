#!/usr/bin/env bash
# Runs each service's own dockerised test suite, one after another, and
# reports which passed. Mirrors each service's `npm run docker:test` without
# needing node on your machine.
#
# Usage: npm test [-- service...]

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

require_docker
require_services_cloned

if [ $# -gt 0 ]; then
  targets=("$@")
else
  targets=("${SERVICES[@]}")
fi

failed=()
for service in "${targets[@]}"; do
  info "Testing $service"
  dir="$(service_dir "$service")"
  test_compose=(docker compose --project-directory "$dir" -f "$dir/compose.yaml" -f "$dir/compose.test.yaml" -p "$service-test")
  "${test_compose[@]}" down --volumes --remove-orphans
  if "${test_compose[@]}" run --build --rm "$service"; then
    ok "$service passed"
  else
    error "$service failed"
    failed+=("$service")
  fi
  "${test_compose[@]}" down --volumes --remove-orphans
done

echo
[ ${#failed[@]} -eq 0 ] || die "Failed: ${failed[*]}"
ok "All tests passed"
