#!/bin/bash

# Function to kill and remove a container
kill_and_remove() {
    container_name=$1
    if sudo podman container kill "$container_name"; then
        echo "Successfully killed $container_name"
    else
        echo "Failed to kill $container_name"
    fi

    if sudo podman container rm "$container_name"; then
        echo "Successfully removed $container_name"
    else
        echo "Failed to remove $container_name"
    fi
}

# Kill and remove mosquitto containers
kill_and_remove mosquitto1
kill_and_remove mosquitto2
kill_and_remove client_sub
# Kill and remove client containers
for i in $(seq 1 10); do
    kill_and_remove "client_pub_$i"
done
sudo podman container prune -y



