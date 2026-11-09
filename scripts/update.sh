#!/usr/bin/env bash
# Pulls the latest default branch for every service, then rebuilds images so
# dependency changes are picked up.
#
# Repos with uncommitted changes, or on a branch other than the default, are
# fetched but not pulled, so in-progress work is never touched.
#
# Usage: npm run update  (or npm run update:no-build)

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

build=true
for arg in "$@"; do
  case "$arg" in
    --no-build) build=false ;;
    -h | --help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown option: $arg" ;;
  esac
done

require_services_cloned

skipped=0
for service in "${SERVICES[@]}"; do
  dir="$(service_dir "$service")"
  info "Updating $service"
  git -C "$dir" fetch --prune --quiet

  branch="$(git -C "$dir" branch --show-current)"
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    warn "$service has uncommitted changes, fetched only"
    skipped=1
  elif [ "$branch" != "$DEFAULT_BRANCH" ]; then
    warn "$service is on '$branch', not '$DEFAULT_BRANCH', fetched only"
    skipped=1
  elif git -C "$dir" pull --ff-only --quiet; then
    ok "$service is up to date with origin/$DEFAULT_BRANCH"
  else
    warn "$service could not fast-forward, resolve it manually"
    skipped=1
  fi
done

if [ "$build" = true ]; then
  require_docker
  info "Rebuilding images"
  compose build --pull
fi

echo
if [ "$skipped" -eq 1 ]; then
  warn "Some services were not pulled, see above. Run npm run status for details"
else
  ok "All services updated"
fi
