#!/bin/bash
# Automatize the insert of sudo password (requested only once)
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
# Step 4: Start MQTT clients
#sudo podman run --name=client_sub --network=newnet --ip=192.168.5.20 -d client_sub
# Step 4: Start 40 MQTT clients dynamically
for i in {1..2}; do
    ip="192.168.5.$((21 + i))"  # IPs from 192.168.5.21 to 192.168.5.60
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" -v /home/vboxuser/Scrivania/LabExp/client_logs:/app/logs -d client_pub 
    
done
# Time to catch some message exchanges before migration
countdown=20
echo "Waiting for $countdown seconds to allow message exchanges..."
while [ $countdown -gt 0 ]; do
    echo -ne "Time remaining: $countdown seconds\r"
    sleep 1
    countdown=$((countdown - 1))
done
echo -ne "\n" 
# Step 5: Automate the Mosquitto database file transfer using rsync
# Here I'm using rsync, but you can also use scp and see the difference 
sudo podman exec -it mosquitto1 sshpass -p "password" rsync -av --no-compress --progress --stats -e "ssh -o StrictHostKeyChecking=no" /mosquitto/mosquitto.db root@192.168.5.11:/mosquitto/mosquitto.db
#time sudo podman exec -it mosquitto1 sshpass -p "password" scp -v -o StrictHostKeyChecking=no /mosquitto/mosquitto.db root@192.168.5.11:/mosquitto/mosquitto.db

echo "Stopping mosquitto1"
migration_start=$(date +%s%N)
# Step 6: Simulate disconnection and migration
sudo podman network disconnect newnet mosquitto1
echo "Starting mosquitto2"
#add broker downtime
sudo podman network disconnect newnet mosquitto2
sleep 10
sudo podman network connect --ip 192.168.5.10 newnet mosquitto2
echo "IP changed"
migration_end=$(date +%s%N)
migration_duration=$(($migration_end - $migration_start))
migration_duration_seconds=$(echo "scale=3; $migration_duration / 1000000000" | bc)
echo "Migration complete. Time spent during migration: ${migration_duration_seconds} seconds"