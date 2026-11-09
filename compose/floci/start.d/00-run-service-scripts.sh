#!/bin/sh
# Runs every service's own floci init scripts, so one shared floci holds the
# AWS resources (buckets, queues etc) that all services expect.
# compose.yaml mounts each service's start.d under /etc/floci/init/services/<service>
set -e

for script in /etc/floci/init/services/*/*.sh; do
  [ -f "$script" ] || continue
  echo "floci init: running $script"
  # The floci image has no bash; it runs init scripts with sh too
  sh "$script"
done
