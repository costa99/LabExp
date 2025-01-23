#!/bin/bash
# Automatize the insert of sudo password (requested only once)
sudo -v 
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
# Set ssh config to make containers communic
#tc qdisc add dev cni-podman1 root tbf rate 10mbit burst 32kbit latency 400ms

copy_sshd_config() {
    container_name=$1
    #local_sshd_config_path="home/labexp24/migration/mqtt_broker/sshd_config"  Adjust this path if necessary
    sudo podman cp /home/vboxuser/Scrivania/LabExp/mqtt_broker/sshd_config "$container_name:/etc/ssh/sshd_config"
    sudo podman exec "$container_name" chmod 600 /etc/ssh/sshd_config  # Set proper permissions
}
# Step 1: Start first Mosquitto broker
sudo podman run --name=mosquitto1 --network=newnet --ip=192.168.5.10 -d mqtt_broker_m
# Step 2: Start second Mosquitto broker
sudo podman run --name=mosquitto2 --network=newnet --ip=192.168.5.11 -d mqtt_broker_m
# Step 3: Setup SSH key-based authentication between the containers
copy_sshd_config mosquitto1
copy_sshd_config mosquitto2

#for veth in $(ifconfig | awk '/^veth/ {print $1}'); do
#    sudo tc qdisc add dev "$veth" root tbf rate 10mbit burst 15k limit 30000
#done
