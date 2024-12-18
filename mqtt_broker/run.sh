#!/bin/sh

# Start the SSH daemon in the background
/usr/sbin/sshd

# Start Mosquitto in the foreground
mosquitto -c /mosquitto/config/mosquitto.conf
