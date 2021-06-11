#!/bin/sh -e

/bin/sh -c 'until swanctl --stats &> /dev/null; do sleep 0.1; done; swanctl --load-all > /proc/1/fd/1' &

exec charon "$@"
