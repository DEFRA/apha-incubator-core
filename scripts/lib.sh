#!/usr/bin/env bash
# Shared helpers for the toolkit scripts. Source it, don't run it.
# Written for macOS's bash 3.2, so no associative arrays or mapfile.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT_DIR/.env"
  set +a
fi

# Every service the toolkit manages. Add new services here and in compose.yaml
SERVICES=(
  apha-risk-insights-backend
  apha-risk-insights-frontend
)

GITHUB_ORG="${GITHUB_ORG:-DEFRA}"
GIT_PROTOCOL="${GIT_PROTOCOL:-ssh}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Relative SERVICES_DIR is relative to this repo, matching how compose resolves it
SERVICES_DIR="${SERVICES_DIR:-..}"
case "$SERVICES_DIR" in
  /*) ;;
  *) SERVICES_DIR="$ROOT_DIR/$SERVICES_DIR" ;;
esac
SERVICES_DIR="$(cd "$SERVICES_DIR" 2>/dev/null && pwd || echo "$SERVICES_DIR")"
# Export the absolute path so docker compose resolves the same directory
export SERVICES_DIR

if [ -t 1 ]; then
  BOLD=$'\033[1m' RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' BLUE=$'\033[34m' RESET=$'\033[0m'
else
  BOLD='' RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

info() { echo "${BLUE}==>${RESET} ${BOLD}$*${RESET}"; }
ok() { echo "${GREEN}✔${RESET} $*"; }
warn() { echo "${YELLOW}!${RESET} $*" >&2; }
error() { echo "${RED}✖${RESET} $*" >&2; }
die() {
  error "$*"
  exit 1
}

service_dir() { echo "$SERVICES_DIR/$1"; }

service_repo_url() {
  if [ "$GIT_PROTOCOL" = "https" ]; then
    echo "https://github.com/$GITHUB_ORG/$1.git"
  else
    echo "git@github.com:$GITHUB_ORG/$1.git"
  fi
}

compose() {
  docker compose --project-directory "$ROOT_DIR" -f "$ROOT_DIR/compose.yaml" "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"
}

require_docker() {
  require_command docker "Install Docker Desktop: https://docs.docker.com/get-docker/"
  docker compose version >/dev/null 2>&1 || die "docker compose v2 is required"
  docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and try again"
}

require_services_cloned() {
  local missing=0 service
  for service in "${SERVICES[@]}"; do
    if [ ! -d "$(service_dir "$service")/.git" ]; then
      error "$service is not cloned in $SERVICES_DIR"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || die "Run npm run setup first"
}
