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

# Step 3: Automate Mosquitto database file transfer
migration_start=$(date +%s%N)

echo "Starting database migration..."


for veth in $(ifconfig | awk '/^veth/ {print $1}'); do
    sudo tc qdisc add dev "$veth" root tbf rate 2gbit burst 15k limit 30000

done
sudo podman exec -it mosquitto1 sshpass -p "password" scp -v \
    -o StrictHostKeyChecking=no /mosquitto/mosquitto.db \
    root@192.168.5.11:/mosquitto/mosquitto.db
#sudo podman exec -it mosquitto1 sshpass -p "password" rsync -avz --progress --human-readable \
#    -e "ssh -o StrictHostKeyChecking=no" /mosquitto/mosquitto.db \
#    root@192.168.5.11:/mosquitto/mosquitto.db

for veth in $(ifconfig | awk '/^veth/ {print $1}'); do
    sudo tc qdisc del dev "$veth" root

done

# Step 4: Simulate broker disconnection and migration
echo "Stopping mosquitto1..."
broker_stop_time=$(date +%s%N)
sudo podman network disconnect newnet mosquitto1

echo "Starting mosquitto2..."
sudo podman network disconnect newnet mosquitto2
sleep 10  # Simulate broker downtime
sudo podman network connect --ip 192.168.5.10 newnet mosquitto2

# Step 5: Log migration duration
migration_end=$(date +%s%N)
migration_duration=$(($migration_end - $migration_start))

broker_downtime_duration=$(($migration_end - $broker_stop_time))
broker_duration_seconds=$(echo "scale=3; $broker_downtime_duration / 1000000000" | bc)
broker_stop_time_human=$(date -d @"$(($broker_stop_time / 1000000000))")

migration_duration_seconds=$(echo "scale=3; $migration_duration / 1000000000" | bc)

echo "Migration complete.\n
Broker mosquitto1 gone ofline at: ${broker_stop_time_human}
Broker donwtime: ${broker_duration_seconds} seconds
Time spent during migration: ${migration_duration_seconds} seconds"

sleep 120
./reset.sh

