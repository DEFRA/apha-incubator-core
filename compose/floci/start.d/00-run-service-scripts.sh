#!/bin/sh
# Runs every service's own floci init scripts, so one shared floci holds the
# AWS resources (buckets, queues etc) that all services expect.
# compose.yaml mounts each service's start.d under /etc/floci/init/services/<service>
#
# A failing script is reported but doesn't stop the rest, and never fails this
# hook: floci shuts down if a hook fails, which would take every service down
# with it. floci keeps its data between restarts, so a script that isn't
# written to be rerun (e.g. a bare `aws s3 mb`) fails on every start after the
# first.

for script in /etc/floci/init/services/*/*.sh; do
  [ -f "$script" ] || continue
  echo "floci init: running $script"
  # The floci image has no bash; it runs init scripts with sh too
  sh "$script" || echo "floci init: WARNING $script failed (exit $?), continuing" >&2
done
