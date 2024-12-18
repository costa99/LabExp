import time
from time import sleep

import paho.mqtt.client as paho
import random
import argparse
import os
import sys
import csv
from datetime import datetime
from threading import Thread

# Global variables
disconnect_time = 0  # To track the time of disconnection
reconnect_time = 0  # To track reconnection timestamp
disconnected = 0  # To flag if the client is disconnected
publish_rate = 0  # Publish rate in messages per second
fails_count = 0
# CSV file setup
csv_file = "/app/logs/mqtt_log.csv"

# Ensure the CSV file exists and write the header only if the file is new
with open(csv_file, mode="w", newline="") as file:
    writer = csv.writer(file)
    writer.writerow(["Client ID", "Disconnect Time", "Reconnect Time", "Fails Count", "Publish Rate (msg/sec)"])

# MQTT Callbacks
def on_connect(client, userdata, flags, rc, properties=None):
    global disconnected

    if disconnected == 0:
        if rc == 0:  # Successful connection
            connect_time = time.time()
            print(f"\nTime: {datetime.fromtimestamp(connect_time)} | Client {client._client_id.decode('utf-8')} connected to the Broker with reason code: {rc}", flush=True)
            client.subscribe('test/topic', qos=1)  # Subscribe to the topic with QoS 1

        else:  # Connection failed
            print(f"\nConnection failed with code {rc}", flush=True)

def generate_large_payload(min_mb, max_mb):
    size_mb = random.uniform(min_mb, max_mb)  # Generate random size within the range
    size_bytes = int(size_mb * 1024 * 1024)  # Convert size from MB to bytes
    return "A" * size_bytes  # Return a string of 'A' characters with the generated size

def publish_msg(client, i):
    global publish_rate, fails_count

    print(f"\nTime: {datetime.fromtimestamp(time.time())} | Client {client._client_id.decode('utf-8')} started to publish", flush=True)
    start_time = time.time()
    success_count = 0  # Counter for successful publishes
    fails_count = 0  # Counter for failed publishes
    fails_disconnection = 0  # Counter for publishes failed during disconnections
    duration = 260  # Total duration to run the publishing in seconds

    global disconnected

    while time.time() - start_time < duration:  # Continue until the duration expires
        payload = generate_large_payload(20, 20)  # Generate a random large payload between 9MB and 10MB
        result = client.publish('test/topic', payload, qos=1, retain=True)  # Publish to the topic with QoS 1 and retain flag
        for i in range(1 , i):
            client.publish(f"test/topic{i}", payload, qos=1, retain=True)
            sleep(1)
        if result[0] == 0:  # If publish is successful
            success_count += 1
        else:  # If publish fails
            fails_count += 1
            if disconnected:  # If the client was disconnected during the failure
                fails_disconnection += 1

        # Calculate remaining time and display status on the same line
        elapsed_time = time.time() - start_time
        remaining_time = max(0, int(duration - elapsed_time))
        publish_rate = success_count / elapsed_time if elapsed_time > 0 else 0
        sys.stdout.write(f"\rSuccess: {success_count} | Fails: {fails_count} | Fails during disconnection: {fails_disconnection} | Total: {success_count + fails_count} | Remaining: {remaining_time} | Rate: {publish_rate:.2f} msg/sec")
        sys.stdout.flush()
        time.sleep(2)  # Small delay to prevent flooding the broker with messages

    # After finishing the publishing loop, print the final statistics
    print(f"\nFinished publishing: Success: {success_count} | Fails: {fails_count} | Fails during disconnection: {fails_disconnection} | Total: {success_count + fails_count}", flush=True)


def on_subscribe(client, userdata, mid, granted_qos, properties=None):
    print(f"\nTime: {datetime.fromtimestamp(time.time())} | Subscribed with QoS {granted_qos}", flush=True)

def handle_disconnect(client, rc):
    global disconnect_time, reconnect_time, disconnected, fails_count
    client_id = client._client_id.decode('utf-8')  # Get the client ID
    disconnected = 1  # Set the disconnected flag
    print(f"\nTime: {datetime.fromtimestamp(disconnect_time)} | Client {client._client_id.decode('utf-8')} disconnected. Reason code: {rc}", flush=True)

    print("\nUnexpected disconnection. Reconnecting...", flush=True)
    retry_count = 0
    MAX_RETRIES = 40  # Maximum number of retry attempts

    while True:
        #if client.is_connected():
        if rc!= 0:
            print("\nTrying to connect...", flush=True)
            if client.is_connected():
                reconnect_time = time.time()
                disconnected = 0  # Clear the disconnected flag
                # Log disconnect and reconnect times, failed count, and publish rate to CSV
                with open(csv_file, mode="a", newline="") as file:
                    writer = csv.writer(file)
                    writer.writerow([
                        client_id,
                        datetime.fromtimestamp(disconnect_time).strftime('%Y-%m-%d %H:%M:%S'),
                        datetime.fromtimestamp(reconnect_time).strftime('%Y-%m-%d %H:%M:%S'),
                        fails_count,
                        round(publish_rate, 2)
                    ])
                print("\nReconnected successfully.", flush=True)
                break

        retry_count += 1
        print(f"\nRetry {retry_count}/{MAX_RETRIES} failed. Retrying in 2 seconds...", flush=True)
        time.sleep(2)  # Wait for 2 seconds before retrying

def on_disconnect(client, userdata, rc):
    global disconnect_time
    disconnect_time = time.time()  # Record the time of disconnection

    disconnect_thread = Thread(target=handle_disconnect, args=(client, rc))
    disconnect_thread.daemon = True  # Make sure the thread ends when the main program ends
    disconnect_thread.start()

# Argument parsing
parser = argparse.ArgumentParser(description='MQTT Client')
parser.add_argument('-o', '--operation', type=str, choices=['sub', 'pub'], default=os.getenv('OPERATION', 'pub'), help='Operation [sub/pub]')
parser.add_argument('-b', '--broker', default=os.getenv('BROKER', "192.168.5.10"), help='Broker IP address')
parser.add_argument('-t', '--topic', default=os.getenv('TOPIC', 'test/topic'), help='MQTT topic to publish to')
parser.add_argument('-r', '--retain', type=bool, default=bool(os.getenv('RETAIN', True)), help='Retain flag')
parser.add_argument('-q', '--qos', type=int, choices=[0, 1, 2], default=int(os.getenv('QOS', 1)), help='Quality of Service')
parser.add_argument('-i', '--interval', type=float, default=float(os.getenv('INTERVAL', 0)), help='Interval between publishes (in seconds)')
parser.add_argument('-c', '--cid', default=os.getenv('CID', str(random.randint(1000, 9999))))
args = parser.parse_args()

# MQTT Client setup
client = paho.Client(client_id=args.cid, protocol=paho.MQTTv311, clean_session=False)
client.on_connect = on_connect  # Assign the on_connect callback
client.on_subscribe = on_subscribe  # Assign the on_subscribe callback
client.on_disconnect = on_disconnect  # Assign the on_disconnect callback

client.connect(args.broker, 1883, keepalive=2)  # Connect to the broker with the provided parameters

# Start publishing in a separate thread
publish_thread = Thread(target=publish_msg, args=(client, 10))
publish_thread.start()  # Start the publish message function in a new thread

# Start the MQTT client loop (this handles background tasks such as keep-alive and incoming messages)
client.loop_forever()
