#!/bin/bash

# Ensure sudo password is requested only once
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

TARGET_SIZE_MB=50

# Step 1: Start MQTT clients dynamically
for i in {1..2}; do
    ip="192.168.5.$((21 + i))"  # Generate IPs dynamically
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" \
        -v /home/vboxuser/Scrivania/LabExp/client_logs:/app/logs -d client_pub
done

# Step 2: Wait to allow message exchanges
countdown=5
echo "Waiting $countdown seconds for message exchanges..."
while [ $countdown -gt 0 ]; do
    echo -ne "Time remaining: $countdown seconds\r"
    sleep 1
    countdown=$((countdown - 1))

done
echo -ne "\n"
#Get the size of mosquitto.db in mosquitto1 container (in bytes)
#db_size=$(sudo podman exec mosquitto1 stat --format="%s" /mosquitto/mosquitto.db)
db_size=$(sudo podman exec mosquitto1 du -b /mosquitto/mosquitto.db | cut -f1)

db_size_mb=$((db_size / 1024 / 1024))  # Size in MB

#Wait for the file to reach the user-defined target size
echo "Starting countdown. Waiting for mosquitto.db to reach $TARGET_SIZE_MB MB..."
while [ $db_size_mb -lt $TARGET_SIZE_MB ]; do
    db_size=$(sudo podman exec mosquitto1 du -b /mosquitto/mosquitto.db | cut -f1)
    db_size_mb=$((db_size / 1024 / 1024))  # Update size in MB

    echo -ne "File size: ${db_size_mb} MB, Target size: ${TARGET_SIZE_MB} MB. \r"

    sleep 1  # Check every second
done


echo "Starting broker migration"
migration_start=$(date +%s)

sudo podman container checkpoint --export=checkpoint.tar mosquitto1
#sudo podman network disconnect mosquitto1 newnet
#sudo podman stop mosquitto1
#sudo podman rm mosquitto1
#echo "starting the new broker"
#sudo podman run --name=mosquitto2 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m
echo "Waiting for broker to start up"
sleep 5
#sudo podman container restore --import=checkpoint.tar --name mosquitto2
#migration_end=$(date +%s)
#migration_duration=$((migration_end - migration_start))
#echo "Migration complete. Time spent during migration: $migration_duration seconds"
