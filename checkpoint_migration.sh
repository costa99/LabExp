#!/bin/bash
# Automatize the insert of sudo password (requested only once)
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
# Set ssh config to make containers communicate
copy_sshd_config() {
    container_name=$1
    local_sshd_config_path="./sshd_config"  # Adjust this path if necessary
    podman cp "$local_sshd_config_path" "$container_name:/etc/ssh/sshd_config"
    podman exec "$container_name" chmod 600 /etc/ssh/sshd_config  # Set proper permissions
}
# Step 1: Start first Mosquitto broker
sudo podman run --name=mosquitto1 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m

# Make sure broker is ready 
sleep 5
# Step 4: Start MQTT clients
# Step 4: Start 40 MQTT clients dynamically
for i in {1..2}; do
    ip="192.168.5.$((21 + i))"  # IPs from 192.168.5.21 to 192.168.5.60
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" -v /home/labexp24/migration/client_logs:/app/logs -d client_pub
    
done
# Time to catch some message exchanges before migration
countdown=10
echo "Waiting for $countdown seconds to allow message exchanges..."
while [ $countdown -gt 0 ]; do
    echo -ne "Time remaining: $countdown seconds\r"
    sleep 1
    countdown=$((countdown - 1))
done
echo -ne "\n" 

sudo podman cp mosquitto1_db/100mb/mosquitto.db mosquitto1:/mosquitto/mosquitto.db

echo "Stoping broker 1 to take chackpoint"
migration_start=$(date +%s%N)
#sudo podman stop mosquitto1
sudo podman container checkpoint --export=checkpoint.tar mosquitto1
sudo podman container rm mosquitto1
echo "starting the new broker"
sudo podman container restore --import=checkpoint.tar --ignore-volumes --name=mosquitto2
migration_end=$(date +%s%N)

# Calculate and display the migration duration
migration_duration=$((migration_end - migration_start))
migration_duration_seconds=$(echo "scale=3; $migration_duration / 1000000000" | bc)
echo "Migration complete. Time spent during migration: $migration_duration_seconds seconds"
