#!/bin/bash
# Automatize the insert of sudo password (requested only once)
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Step 1: Start first Mosquitto broker
sudo podman run --name=mosquitto1 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m
sleep 5
# Step 4: Start MQTT clients
for i in {1..3}; do
    ip="192.168.5.$((21 + i))"  # IPs from 192.168.5.21 to 192.168.5.60
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" -d client_pub
    
done
# Time to catch some message exchanges before migration
countdown=15
echo "Waiting for $countdown seconds to allow message exchanges..."
sleep $countdown

echo "Starting broker migration"
migration_start=$(date +%s)

sudo podman container checkpoint --export=checkpoint.tar mosquitto1
#sudo podman network disconnect mosquitto1 newnet
sudo podman stop mosquitto1
sudo podman rm mosquitto1
echo "starting the new broker"
sudo podman run --name=mosquitto2 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m
echo "Waiting for broker to start up"
sleep 5
sudo podman container restore --import=checkpoint.tar mosquitto2
migration_end=$(date +%s)
migration_duration=$((migration_end - migration_start))
echo "Migration complete. Time spent during migration: $migration_duration seconds"
