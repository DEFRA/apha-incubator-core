#!/usr/bin/env bash
# Seeds local data, so the services have something to work with:
#   1. uploads the ingestion service's WAHIS fixtures (a real sample) to S3 as
#      raw data, skipped if they are already there
#   2. runs the ingestion service's WAHIS transform over the raw data, writing
#      one outbreak record per outbreak under transformed/
#   3. loads each service's synthetic data (six months of made-up records) by
#      running its synthetic-data/seed.sh. See docs/synthetic-data.md
#
# Safe to rerun. To start again from nothing, run npm run stop:clean first.
#
# Usage: npm run seed [-- options] [-- service...]
#   e.g. npm run seed -- --synthetic-only
#        npm run seed -- --limit 5
#        npm run seed -- apha-risk-insights-backend
#   --synthetic-only  skip steps 1 and 2: load synthetic data only
#   --clear           remove the synthetic data, and nothing else
#                     (npm run seed:clear)
#   --limit N         passed to the transform
#   --dry-run         run the transform without writing; loads nothing
#   service...        seed only these services (the real sample is ingestion's)

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

INGESTION=apha-insights-ingestion
BUCKET=apha-insights-ingestion-local

clear=false
real=true
dry_run=false
transform_args=()
targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    --clear) clear=true ;;
    --synthetic-only) real=false ;;
    --dry-run)
      dry_run=true
      transform_args+=(--dry-run)
      ;;
    --limit)
      [ $# -ge 2 ] || die "--limit needs a number"
      transform_args+=(--limit "$2")
      shift
      ;;
    -h | --help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) die "Unknown option: $1" ;;
    *) targets+=("$1") ;;
  esac
  shift
done

[ ${#targets[@]} -gt 0 ] || targets=("${SERVICES[@]}")
if [ "$real" = false ] && [ ${#transform_args[@]} -gt 0 ]; then
  die "--limit and --dry-run apply to the real sample, so not with --synthetic-only"
fi

require_docker
require_services_cloned
[ -n "$(compose ps --quiet --status running floci)" ] || die "floci is not running. Run npm start first"

seeds_ingestion=false
for service in "${targets[@]}"; do
  [ "$service" != "$INGESTION" ] || seeds_ingestion=true
done

FIXTURE_SCRIPT=20-seed-wahis-fixtures.sh

# The real sample runs first: the transform reads every raw outbreak,
# synthetic ones included, so the synthetic step must replace what it writes
if [ "$clear" = false ] && [ "$real" = true ] && [ "$seeds_ingestion" = true ]; then
  info "Seeding raw WAHIS fixtures"
  # Run the ingestion service's own seed script in a throwaway container from
  # the floci image, which has the aws CLI. floci doesn't mount the fixtures
  # itself, so npm start leaves the bucket empty and --synthetic-only can give
  # a stack with no real data at all
  ingestion_dir="$(service_dir "$INGESTION")"
  docker run --rm --network apha-risk \
    --volume "$ingestion_dir/fixtures:/fixtures/wahis:ro" \
    --volume "$ingestion_dir/compose/floci/start.d/$FIXTURE_SCRIPT:/seed.sh:ro" \
    --env AWS_ENDPOINT_URL=http://floci:4566 \
    --env AWS_ACCESS_KEY_ID=test --env AWS_SECRET_ACCESS_KEY=test \
    --env AWS_DEFAULT_REGION=eu-west-2 \
    --entrypoint sh \
    "$(docker inspect --format '{{.Config.Image}}' "$(compose ps --quiet floci)")" /seed.sh

  info "Transforming raw WAHIS outbreaks"
  # The transform script isn't in the service's image, so mount it. --no-deps:
  # floci is already up and the transform doesn't use MongoDB
  # ${arr[@]+...} because bash 3.2 treats an empty array as unset under set -u
  compose run --rm --no-deps --quiet-pull \
    --volume "$(service_dir "$INGESTION")/scripts:/home/node/scripts:ro" \
    --env "S3_ENDPOINT_URL=http://floci:4566" \
    --env "S3_BUCKET=$BUCKET" \
    "$INGESTION" node scripts/transform-wahis.js ${transform_args[@]+"${transform_args[@]}"}
fi

if [ "$dry_run" = true ]; then
  ok "Dry run: nothing written"
  exit 0
fi

# Data from before --synthetic-only existed, or from a seed without it
if [ "$clear" = false ] && [ "$real" = false ] && [ "$seeds_ingestion" = true ]; then
  fixture_date="$(sed -n 's/^DATE=//p' "$(service_dir "$INGESTION")/compose/floci/start.d/$FIXTURE_SCRIPT")"
  if compose exec -T floci aws s3api head-object --bucket "$BUCKET" \
    --key "raw/wahis/$fixture_date/event-filtered-list.json" >/dev/null 2>&1; then
    warn "The bucket still holds the real WAHIS sample from an earlier seed."
    warn "For synthetic data only: npm run stop:clean && npm start && npm run seed -- --synthetic-only"
  fi
fi

# Ingestion goes first: the backend's synthetic WAHIS outbreaks are copied
# from the data the ingestion service generates
ordered=()
[ "$seeds_ingestion" = false ] || ordered=("$INGESTION")
for service in "${targets[@]}"; do
  [ "$service" = "$INGESTION" ] || ordered+=("$service")
done

failed=()
for service in "${ordered[@]}"; do
  script="$(service_dir "$service")/synthetic-data/seed.sh"
  if [ ! -f "$script" ]; then
    warn "$service has no synthetic data, skipping"
    continue
  fi
  if [ "$clear" = true ]; then
    info "Removing $service synthetic data"
    "$script" --clear || failed+=("$service")
  else
    info "Seeding $service synthetic data"
    "$script" || failed+=("$service")
  fi
done

echo
[ ${#failed[@]} -eq 0 ] || die "Failed: ${failed[*]}"
if [ "$clear" = true ]; then
  ok "Synthetic data removed"
  exit 0
fi

count() { compose exec -T floci aws s3 ls "s3://$BUCKET/$1" --recursive | wc -l | tr -d ' '; }

ok "Seeded"
echo "  s3://$BUCKET: $(count raw/) raw objects, $(count transformed/) transformed records"
echo "Browse it with npm run s3:local in $INGESTION, or:"
echo "  aws --endpoint-url=http://localhost:4566 s3 ls s3://$BUCKET --recursive"
