#!/bin/bash
# Auto-start containers that Coolify leaves stuck in "Created" state.
# Targets any container with coolify.managed=true that hasn't started.
while true; do
    docker ps -a \
        --filter "status=created" \
        --filter "label=coolify.managed=true" \
        --format "{{.ID}} {{.Names}}" \
    | while read -r id name; do
        echo "[$(date -u +%H:%M:%S)] Starting stuck container: $name ($id)"
        docker start "$id"
    done
    sleep 10
done
