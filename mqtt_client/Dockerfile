FROM python:3.9-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY mqtt_client.py /app/

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir paho-mqtt


# Make port 1883 available to the world outside this container (for MQTT communication)
EXPOSE 1883

# Run the client script
ENTRYPOINT ["python", "./mqtt_client.py"]

# -o sub/pub
# -t "testing"
# -p “test message"
# -r True
# -q 0/1/2
# -i 5
# -c 1234
