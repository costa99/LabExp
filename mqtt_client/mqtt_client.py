import time
from time import sleep

import paho.mqtt.client as paho
import random
import argparse
import os
import sys
import csv
from datetime import datetime
from threading import Thread, Event

# Global variables
initial_connection = True
db_generate = True
index = 1
disconnect_time = 0  # To track the time of disconnection
reconnect_time = 0  # To track reconnection timestamp
disconnected = Event()  # To flag if the client is disconnected
publish_rate = 0  # Publish rate in messages per second
fails_count = 0
success_count = 0
received_counter = 0
stop_publishing = Event()
# CSV file setup
csv_file = "/app/logs/mqtt_log.csv"

# Ensure the CSV file exists and write the header only if the file is new
with open(csv_file, mode="w", newline="") as file:
    writer = csv.writer(file)
    writer.writerow(["Client ID", "Disconnect Time", "Reconnect Time","Disconnection duration", "Fails Count", "Publish Rate (msg/sec)"])

# MQTT Callbacks
def on_connect(client, userdata, flags, rc, properties=None):
    global initial_connection
    client.subscribe('test/topic', qos=1)  # Subscribe to the topic with QoS 1

    if rc == 0:
            connect_time = time.time()
            print(f"\nTime: {datetime.fromtimestamp(connect_time)} | Client {client._client_id.decode('utf-8')} connected to the Broker with reason code: {rc}", flush=True)
            if initial_connection:
                initial_connection = False
            else:
                reconnect_time = time.time()
                disconnection_duration = reconnect_time - disconnect_time
                client_id = client._client_id.decode('utf-8')  # Get the client ID
                # Log disconnect and reconnect times, failed count, and publish rate to CSV
                with open(csv_file, mode="a", newline="") as file:
                    writer = csv.writer(file)
                    writer.writerow([
                        client_id,
                        datetime.fromtimestamp(disconnect_time).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
                        datetime.fromtimestamp(reconnect_time).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
                        round(disconnection_duration, 3),
                        fails_count,
                        round(publish_rate, 2)
                    ])
                print(f"\nReconnected successfully after {disconnection_duration}.", flush=True)
                   # Clear the stop event and restart publishing
                stop_publishing.clear()
                publish_thread = Thread(target=publish_msg, args=(client,100))
                publish_thread.start()

            disconnected.clear()
            stop_publishing.clear()


    else:  # Connection failed
            print(f"\nConnection failed with code {rc}", flush=True)

def on_message(client, userdata, msg):
    global received_counter
    """Callback to handle incoming messages."""
    received_counter += 1
    #print(f"\nTime: {datetime.fromtimestamp(time.time())} | Message received on topic '{msg.topic}': {msg.payload.decode('utf-8')}", flush=True)


def generate_large_payload(min_mb, max_mb):
    size_mb = random.uniform(min_mb, max_mb)  # Generate random size within the range
    size_bytes = int(size_mb * 1024 * 1024)  # Convert size from MB to bytes
    return "A" * size_bytes  # Return a string of 'A' characters with the generated size

def publish_msg(client, duration):
    global publish_rate, success_count, fails_count, index, db_generate

    fails_disconnection = 0  # Counter for publishes failed during disconnections

    while not stop_publishing.is_set():
        print(f"\nTime: {datetime.fromtimestamp(time.time())} | Client {client._client_id.decode('utf-8')} publishing", flush=True)

        # Check if publishing should stop (e.g., on disconnection)
        # Publish a message without a payload to the 'topic'
        result_no_payload = client.publish('test/topic', qos=1, retain=True)

        # Generate a random large payload (between 1MB and 2MB)
        payload = generate_large_payload(1, 2)

        # Publish the large payload to a topic with an increasing index
        if db_generate:
            result_with_payload = client.publish(f"test/topic{index}", payload, qos=1, retain=True)

        # Increment the topic index for the next message
        index += 1

        # Track the results of the publish attempts
        if result_no_payload[0] == 0:  # Success for the message without payload
            success_count += 1
        else:  # Failure for the message without payload
            fails_count += 1
            if disconnected.is_set():  # If the client was disconnected during the failure
                fails_disconnection += 1
        print(f"succes: {success_count}, fails: {fails_count}, received: {received_counter}", end="\r", flush=True)
        # Calculate remaining time and display status on the same line
        #elapsed_time = time.time() - start_time
        #remaining_time = max(0, int(duration - elapsed_time))
        #publish_rate = success_count / elapsed_time if elapsed_time > 0 else 0
        #print(f"\rSuccess: {success_count} | Fails: {fails_count} | Fails during disconnection: {fails_disconnection} | Total: {success_count + fails_count} | Remaining: {remaining_time} | Rate: {publish_rate:.2f} msg/sec")

        time.sleep(2)  # Delay of 2 seconds between publish attempts

        if index >= duration:
            break  # Exit the loop once the duration is met

    # After finishing the publishing loop, print the final statistics
    print(f"\nFinished publishing: Success: {success_count} | Fails: {fails_count} | Fails during disconnection: {fails_disconnection} | Total: {success_count + fails_count}", flush=True)


def on_subscribe(client, userdata, mid, granted_qos, properties=None):
    print(f"\nTime: {datetime.fromtimestamp(time.time())} | Subscribed with QoS {granted_qos}", flush=True)

def easy_disconnection(client, userdata, rc):
    if rc!=0:
        global disconnect_time, db_generate
        disconnect_time = time.time()
        disconnected.set()  # Signal disconnection
        stop_publishing.set()  # Pause publishing
        db_generate = False
        print("Unexpected disconnection. Will auto-reconnect")

def handle_disconnect(client, userdata, rc):
    global disconnect_time, reconnect_time

    disconnect_time = time.time()
    client_id = client._client_id.decode('utf-8')  # Get the client ID
    disconnected.set()  # Signal disconnection
    stop_publishing.set()  # Pause publishing

    print(f"\nTime: {datetime.fromtimestamp(disconnect_time)} | Client {client._client_id.decode('utf-8')} disconnected. Reason code: {rc}", flush=True)
    print("\nUnexpected disconnection. Reconnecting...", flush=True)

    retry_count = 0
    MAX_RETRIES = 40  # Maximum number of retry attempts

    while True:
        if rc != 0:
            print("\nTrying to reconnect...", flush=True)
            try:
                client.reconnect()
                reconnect_time = time.time()
                disconnection_duration = reconnect_time - disconnect_time

                # Log disconnect and reconnect times, failed count, and publish rate to CSV
                with open(csv_file, mode="a", newline="") as file:
                    writer = csv.writer(file)
                    writer.writerow([
                        client_id,
                        datetime.fromtimestamp(disconnect_time).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
                        datetime.fromtimestamp(reconnect_time).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
                        round(disconnection_duration, 3),
                        fails_count,
                        round(publish_rate, 2)
                    ])
                print("\nReconnected successfully.", flush=True)
                   # Clear the stop event and restart publishing
                stop_publishing.clear()
                publish_thread = Thread(target=publish_msg, args=(client,100))
                publish_thread.start()
                break

            except Exception as e:
                retry_count += 1
                print(f"\nRetry {retry_count}/{MAX_RETRIES} failed. Retrying in 2 seconds...", flush=True)
                time.sleep(2)  # Wait before retrying

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
client.on_disconnect = easy_disconnection  # Assign the on_disconnect callback
client.on_message = on_message  # Assign the on_message callback
client.connect(args.broker, 1883, keepalive=1)  # Connect to the broker with the provided parameters

# Start publishing in a separate thread
publish_thread = Thread(target=publish_msg, args=(client, 400))
publish_thread.start()  # Start the publish message function in a new thread

# Start the MQTT client loop (this handles background tasks such as keep-alive and incoming messages)
client.loop_forever()
