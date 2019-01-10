#!/bin/bash


create_docker_network() {
    network_found=$(docker network ls  --format '{{.Name}}' --filter name=$network)
    if [[ ! "$network_found" ]]; then
        docker network create --driver bridge --subnet=10.1.2.0/24 \
            -o com.docker.network.bridge.name=br-$network $network  \
            || (rc=$?; echo "'docker network create' failed with code=${rc}"; exit $rc)
    fi
}


remove_container_if_not_running() {
    local status=$(docker container inspect -f '{{.State.Status}}' $container 2>/dev/null || echo '')
    if [[ "$status" ]]; then
        docker container rm -f $container >/dev/null 2>&1 \
            || (rc=$?; echo "'docker container rm $container' failed with code=${rc}"; exit $rc)
    fi
}


remove_containers() {
    for cont in $*; do
        local container_found=$(docker container inspect -f '{{.Name}}' $cont 2>/dev/null || true)
        if [[ "$container_found" ]]; then
            docker container rm -f $container_found -v |  perl -pe 'chomp; print " removed\n"' \
            || (rc=$?; echo "'docker container rm $container_found' failed with code=${rc}"; exit $rc)
        fi
    done
}


remove_volumes() {
    for vol in $*; do
        volume_found=$(docker volume ls --format '{{.Name}}' --filter name=^$vol$)
        if [[ "$volume_found" ]]; then
            docker volume rm $volume_found && perl -pe 'chomp; print " removed\n"' \
            || (rc=$?; echo "'docker volume rm $volume_found' failed with code=${rc}"; exit $rc)
        fi
    done
}
