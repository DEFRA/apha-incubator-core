#!/usr/bin/env bash
# Seeds local data, so the services have something to work with:
#   1. uploads the ingestion service's WAHIS fixtures to S3 as raw data
#      (start does this too; it is skipped if they are already there)
#   2. runs the ingestion service's WAHIS transform over the raw data, writing
#      one outbreak record per outbreak under transformed/
#
# Safe to rerun. To start again from nothing, run npm run stop:clean first.
#
# Usage: npm run seed [-- transform options]
#   e.g. npm run seed -- --limit 5
#        npm run seed -- --dry-run

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

INGESTION=apha-insights-ingestion
BUCKET=apha-insights-ingestion-local

require_docker
require_services_cloned
[ -n "$(compose ps --quiet --status running floci)" ] || die "floci is not running. Run npm start first"

info "Seeding raw WAHIS fixtures"
compose exec -T floci sh "/etc/floci/init/services/$INGESTION/20-seed-wahis-fixtures.sh"

info "Transforming raw WAHIS outbreaks"
# The transform script isn't in the service's image, so mount it. --no-deps:
# floci is already up and the transform doesn't use MongoDB
compose run --rm --no-deps --quiet-pull \
  --volume "$(service_dir "$INGESTION")/scripts:/home/node/scripts:ro" \
  --env "S3_ENDPOINT_URL=http://floci:4566" \
  --env "S3_BUCKET=$BUCKET" \
  "$INGESTION" node scripts/transform-wahis.js "$@"

count() { compose exec -T floci aws s3 ls "s3://$BUCKET/$1" --recursive | wc -l | tr -d ' '; }

echo
ok "Seeded s3://$BUCKET: $(count raw/) raw objects, $(count transformed/) transformed records"
echo "Browse it with npm run s3:local in $INGESTION, or:"
echo "  aws --endpoint-url=http://localhost:4566 s3 ls s3://$BUCKET --recursive"
