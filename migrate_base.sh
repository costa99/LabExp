#!/bin/bash
# Automatize the insert of sudo password (requested only once)
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
# Set ssh config to make containers communic
#tc qdisc add dev cni-podman1 root tbf rate 10mbit burst 32kbit latency 400ms

copy_sshd_config() {
    container_name=$1
    #local_sshd_config_path="home/labexp24/migration/mqtt_broker/sshd_config"  Adjust this path if necessary
    sudo podman cp /home/labexp24/migration/mqtt_broker/sshd_config "$container_name:/etc/ssh/sshd_config"
    sudo podman exec "$container_name" chmod 600 /etc/ssh/sshd_config  # Set proper permissions
}
# Step 1: Start first Mosquitto broker
sudo podman run --name=mosquitto1 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m
# Step 2: Start second Mosquitto broker
sudo podman run --name=mosquitto2 --network=newnet --ip=192.168.5.11 -d mqtt_broker_m
# Step 3: Setup SSH key-based authentication between the containers
copy_sshd_config mosquitto1
copy_sshd_config mosquitto2
# Make sure broker is ready 
sleep 5
# Step 4: Start MQTT clients
#sudo podman run --name=client_sub --network=newnet --ip=192.168.5.20 -d client_sub
# Step 4: Start 40 MQTT clients dynamically
for i in {1..2}; do
    ip="192.168.5.$((21 + i))"  # IPs from 192.168.5.21 to 192.168.5.60
    sudo podman run --name="client_pub_$i" --network=newnet --ip="$ip" -v /home/labExp/client_logs:/app/logs -d client_pub 
    
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
# Step 6: Simulate disconnection and migration
sudo podman network disconnect newnet mosquitto1
echo "Starting mosquitto2"
#add broker downtime
sudo podman network disconnect newnet mosquitto2
sleep 2
sudo podman network connect --ip 192.168.5.10 newnet mosquitto2
echo "IP changed"