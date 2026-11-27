#!/usr/bin/env bash
# Starts every service and its dependencies on the apha-risk docker network,
# then waits until each service answers its health check.
#
# Usage: npm start [-- --build --debug --ci [--published=SERVICES] --logs]
#   or npm run start:build, start:debug, start:ci, start:logs
#   --build  rebuild images first (needed after package.json changes)
#   --debug  start node with --inspect-brk; services wait for a debugger
#   --ci     run production images built from each checkout, with no source
#            mounted (compose.ci.yaml). Implies --build. This is what CI runs
#   --published=SERVICES
#            with --ci: pull the image CDP published from main
#            (defradigital/<service>:latest) for these services instead of
#            building them. Comma-separated service names, or "all"
#   --logs   follow logs after starting

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

up_args=(up --detach --remove-orphans)
compose_files=()
follow_logs=false
debug=false
ci=false
published_arg=""
for arg in "$@"; do
  case "$arg" in
    --build) up_args+=(--build) ;;
    --debug) debug=true ;;
    --ci) ci=true ;;
    --published=*) published_arg="${arg#--published=}" ;;
    --logs) follow_logs=true ;;
    -h | --help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown option: $arg" ;;
  esac
done

[ "$debug" = true ] && [ "$ci" = true ] && die "--debug and --ci can't be used together"
[ -n "$published_arg" ] && [ "$ci" != true ] && die "--published only works with --ci"
[ "$debug" = true ] && compose_files+=(-f "$ROOT_DIR/compose.debug.yaml")

# In CI mode, split the services into those to pull from Docker Hub and those
# to build from their checkout
published=()
to_build=()
if [ "$ci" = true ]; then
  compose_files+=(-f "$ROOT_DIR/compose.ci.yaml")
  if [ "$published_arg" = all ]; then
    published=("${SERVICES[@]}")
  elif [ -n "$published_arg" ]; then
    IFS=, read -r -a published <<<"$published_arg"
    for service in "${published[@]}"; do
      case " ${SERVICES[*]} " in
        *" $service "*) ;;
        *) die "--published: unknown service $service. Expected: ${SERVICES[*]}" ;;
      esac
    done
  fi
  for service in "${SERVICES[@]}"; do
    case " ${published[*]-} " in
      *" $service "*)
        # compose.ci.yaml reads the image name from CI_IMAGE_<SERVICE>
        var="CI_IMAGE_$(echo "$service" | tr '[:lower:]-' '[:upper:]_')"
        export "$var=defradigital/$service:latest"
        ;;
      *) to_build+=("$service") ;;
    esac
  done
fi

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
for name in $(compose ${compose_files[@]+"${compose_files[@]}"} config | awk '/container_name:/ { print $2 }'); do
  project="$(docker ps --all --filter "name=^/${name}$" --format '{{.Label "com.docker.compose.project"}}')"
  [ -z "$project" ] || [ "$project" = "apha-risk-insights" ] && continue
  if [ "$(docker inspect --format '{{.State.Running}}' "$name")" = true ]; then
    die "$name is running from project $project. Stop it first, e.g. 'npm run docker:stop' in that service repo"
  fi
  docker rm "$name" >/dev/null
  ok "Removed stopped $name left by project $project"
done

# The ${a[@]+...} form keeps bash 3.2 happy when the array is empty under set -u
if [ "$ci" = true ]; then
  # Build and pull explicitly, then start without building, so published
  # services are never rebuilt. compose build with no services would build all
  if [ ${#to_build[@]} -gt 0 ]; then
    info "Building ${to_build[*]}"
    compose "${compose_files[@]}" build "${to_build[@]}"
  fi
  if [ ${#published[@]} -gt 0 ]; then
    info "Pulling published images for ${published[*]}"
    compose "${compose_files[@]}" pull "${published[@]}"
  fi
  up_args=(up --detach --remove-orphans --no-build)
fi

info "Starting services"
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

if [ "$debug" = true ]; then
  warn "Debug mode: services wait for a debugger on localhost:9229 (backend), 9230 (frontend), 9231 (ingestion) and 9232 (backoffice)"
else
  info "Waiting for services to be healthy"
  healthy=true
  wait_for_health apha-risk-insights-backend http://localhost:3001/health || healthy=false
  wait_for_health apha-risk-insights-frontend http://localhost:3000/health || healthy=false
  wait_for_health apha-insights-ingestion http://localhost:3002/health || healthy=false
  wait_for_health apha-insights-backoffice http://localhost:3003/health || healthy=false
fi

cat <<EOF

${BOLD}Services${RESET}
  Frontend         http://localhost:3000
  Backend          http://localhost:3001
  Backend API docs http://localhost:3001/documentation
  Ingestion        http://localhost:3002
  Backoffice       http://localhost:3003

${BOLD}Infrastructure${RESET}
  MongoDB          mongodb://localhost:27017 (backend)
  MongoDB          mongodb://localhost:27018 (ingestion)
  Redis            localhost:6379 (frontend)
  Redis            localhost:6380 (backoffice)
  floci (AWS)      http://localhost:4566

Stop with npm run stop, follow logs with npm run logs, load sample data with npm run seed
EOF

if [ "$follow_logs" = true ]; then
  compose logs --follow
fi

[ "${healthy:-true}" = true ]
