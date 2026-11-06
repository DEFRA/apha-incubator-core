#!/usr/bin/env bash
# Shows each service's git state (branch, uncommitted changes, ahead/behind
# origin) and which containers are running.
#
# Usage: npm run status

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

info "Repositories ($SERVICES_DIR)"
printf '  %-32s %-36s %s\n' SERVICE BRANCH STATE
for service in "${SERVICES[@]}"; do
  dir="$(service_dir "$service")"
  if [ ! -d "$dir/.git" ]; then
    printf '  %-32s %-36s %s\n' "$service" - "${RED}not cloned${RESET}"
    continue
  fi

  branch="$(git -C "$dir" branch --show-current)"
  state=()
  [ -n "$(git -C "$dir" status --porcelain)" ] && state+=("${YELLOW}uncommitted changes${RESET}")
  if counts="$(git -C "$dir" rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null)"; then
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"
    [ "$ahead" -gt 0 ] && state+=("$ahead ahead")
    [ "$behind" -gt 0 ] && state+=("${YELLOW}$behind behind${RESET}")
  else
    state+=("no upstream")
  fi
  [ ${#state[@]} -eq 0 ] && state=("${GREEN}clean${RESET}")

  printf '  %-32s %-36s %s\n' "$service" "$branch" "$(
    IFS=,
    echo "${state[*]}" | sed 's/,/, /g'
  )"
done

echo
info "Containers"
if docker info >/dev/null 2>&1; then
  compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
else
  warn "Docker is not running"
fi
