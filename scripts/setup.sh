#!/usr/bin/env bash
# First-time setup for a new developer: checks prerequisites, clones every
# service and builds the images. Dependencies are installed inside the images,
# so nothing is installed on your machine.
#
# Usage: npm run setup

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

for arg in "$@"; do
  case "$arg" in
    -h | --help)
      sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown option: $arg" ;;
  esac
done

info "Checking prerequisites"
require_command git "Install it from https://git-scm.com"
require_docker
ok "git and docker are ready"

if [ ! -f "$ROOT_DIR/.env" ]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  ok "Created .env from .env.example"
fi

mkdir -p "$SERVICES_DIR"
info "Cloning services into $SERVICES_DIR"
for service in "${SERVICES[@]}"; do
  dir="$(service_dir "$service")"
  if [ -d "$dir/.git" ]; then
    ok "$service already cloned"
  else
    git clone "$(service_repo_url "$service")" "$dir"
    ok "Cloned $service"
  fi
done

info "Building images"
compose build

echo
ok "Setup complete. Start everything with ${BOLD}npm start${RESET}"
