#!/bin/bash
set -euo pipefail

host="${WORDPRESS_HOST:-wordpress}"
port="${WORDPRESS_PORT:-9000}"
attempts=0
max_attempts=60

until nc -z "${host}" "${port}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
        echo "Error: ${host}:${port} did not become reachable within 120 seconds." >&2
        exit 1
    fi
    echo "Waiting for ${host}:${port}..."
    sleep 2
done

echo "${host}:${port} is reachable. Starting NGINX..."
exec nginx -g "daemon off;"
