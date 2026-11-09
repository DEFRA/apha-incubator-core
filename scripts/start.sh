#!/usr/bin/env bash
# Starts every service and its dependencies on the apha-risk docker network,
# then waits until each service answers its health check.
#
# Usage: npm start [-- --build --debug --logs]
#   or npm run start:build, start:debug, start:logs
#   --build  rebuild images first (needed after package.json changes)
#   --debug  start node with --inspect-brk; services wait for a debugger
#   --logs   follow logs after starting

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

up_args=(up --detach --remove-orphans)
compose_files=()
follow_logs=false
for arg in "$@"; do
  case "$arg" in
    --build) up_args+=(--build) ;;
    --debug) compose_files=(-f "$ROOT_DIR/compose.debug.yaml") ;;
    --logs) follow_logs=true ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown option: $arg" ;;
  esac
done

require_docker
require_services_cloned

# A service started from its own repo joins the same network with its own
# floci/mongodb/redis, giving two containers per hostname. Refuse rather than
# let requests land on the wrong one.
others="$(docker ps --filter network=apha-risk --format '{{.Names}} {{.Label "com.docker.compose.project"}}' |
  awk '$2 != "apha-risk-insights" { print $1 " (project " $2 ")" }')"
if [ -n "$others" ]; then
  error "Containers from other compose projects are on the apha-risk network:"
  echo "$others" >&2
  die "Stop them first, e.g. 'npm run docker:stop' in that service repo"
fi

# Service repos give their app containers fixed names, so a stopped container
# left by a service's own compose project blocks ours. Compose won't adopt a
# container from another project, so remove it; the image is kept, so the
# replacement is created without a rebuild.
for name in $(compose config | awk '/container_name:/ { print $2 }'); do
  project="$(docker ps --all --filter "name=^/${name}$" --format '{{.Label "com.docker.compose.project"}}')"
  [ -z "$project" ] || [ "$project" = "apha-risk-insights" ] && continue
  if [ "$(docker inspect --format '{{.State.Running}}' "$name")" = true ]; then
    die "$name is running from project $project. Stop it first, e.g. 'npm run docker:stop' in that service repo"
  fi
  docker rm "$name" >/dev/null
  ok "Removed stopped $name left by project $project"
done

info "Starting services"
# The ${a[@]+...} form keeps bash 3.2 happy when the array is empty under set -u
compose ${compose_files[@]+"${compose_files[@]}"} "${up_args[@]}"

wait_for_health() {
  local name="$1" url="$2" attempts=60
  until curl --silent --fail --output /dev/null "$url"; do
    attempts=$((attempts - 1))
    if [ "$attempts" -eq 0 ]; then
      warn "$name did not become healthy. Check npm run logs -- $name"
      return 1
    fi
    sleep 2
  done
  ok "$name is healthy"
}

if [ ${#compose_files[@]} -gt 0 ]; then
  warn "Debug mode: services wait for a debugger on localhost:9229 (backend), 9230 (frontend) and 9231 (ingestion)"
else
  info "Waiting for services to be healthy"
  healthy=true
  wait_for_health apha-risk-insights-backend http://localhost:3001/health || healthy=false
  wait_for_health apha-risk-insights-frontend http://localhost:3000/health || healthy=false
  wait_for_health apha-insights-ingestion http://localhost:3002/health || healthy=false
fi

cat <<EOF

${BOLD}Services${RESET}
  Frontend         http://localhost:3000
  Backend          http://localhost:3001
  Backend API docs http://localhost:3001/documentation
  Ingestion        http://localhost:3002

${BOLD}Infrastructure${RESET}
  MongoDB          mongodb://localhost:27017 (backend)
  MongoDB          mongodb://localhost:27018 (ingestion)
  Redis            localhost:6379
  floci (AWS)      http://localhost:4566

Stop with npm run stop, follow logs with npm run logs
EOF

if [ "$follow_logs" = true ]; then
  compose logs --follow
fi

[ "${healthy:-true}" = true ]
