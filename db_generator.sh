#!/bin/bash

# Automatically maintain sudo permissions
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Function to copy SSH configuration file to a container
copy_sshd_config() {
    container_name=$1
    local_sshd_config_path="./sshd_config"  # Adjust this path if necessary
    podman cp "$local_sshd_config_path" "$container_name:/etc/ssh/sshd_config"
    podman exec "$container_name" chmod 600 /etc/ssh/sshd_config
}

# Step 1: Start Mosquitto broker
sudo podman run --name=mosquitto1 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m

# Wait for the broker to be ready
sleep 5

# Step 2: Start MQTT clients
#sudo podman run --name=client_sub --network=newnet --ip=192.168.5.20 -d client_sub

# Start 20 MQTT publisher clients dynamically
for i in {1..6}; do
    ip="192.168.5.$((21 + i))"  # IPs from 192.168.5.21 to 192.168.5.40
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" -v /home/vboxuser/Scrivania/LabExp/client_logs:/app/logs -d client_pub 
done

# Step 3: Monitor database file size and stop if it reaches 200MB
host_db_path="mosquitto1_db/mosquitto.db"
sudo mkdir -p ./mosquitto1_db  # Ensure the host directory exists

sudo podman exec mosquitto1 mkdir -p /tmp/mosquitto_backup
while true; do
    # Verify if the database file exists inside the container
    if sudo podman exec mosquitto1 test -f /mosquitto/mosquitto.db; then
        # Copy the database file from the container to the host
        sudo podman exec mosquitto1 cp /mosquitto/mosquitto.db /tmp/mosquitto_backup/
        sudo podman cp mosquitto1:/tmp/mosquitto_backup/mosquitto.db "$host_db_path"
    else
        echo "Database file does not exist in the container. Retrying..."
        sleep 5
        continue
    fi

    # Verify if the database file was successfully copied to the host
    if [ -f "$host_db_path" ]; then
        db_size_bytes=$(stat --printf="%s" "$host_db_path")  # Get file size in bytes
        db_size_mb=$(echo "scale=2; $db_size_bytes / (1024 * 1024)" | bc)  # Convert to MB
        echo "Current database size: ${db_size_mb}MB (${db_size_bytes} bytes)"
        if [ "$db_size_bytes" -ge $((200 * 1024 * 1024)) ]; then
            echo "Database file size has reached 200MB. Stopping..."
            break
        fi
    else
        echo "Database file does not exist on the host. Retrying..."
    fi

    sleep 30  # Check the size every 10 seconds
done

echo "Database file copied to host at $host_db_path"
