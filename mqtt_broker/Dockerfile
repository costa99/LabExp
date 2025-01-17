# Use the official Eclipse Mosquitto image as the base image
FROM eclipse-mosquitto:latest

# Install rsync and openssh sshpass iperf3
RUN apk add --no-cache rsync openssh sshpass iperf3

# Copy mosquitto.conf
COPY mosquitto.conf /mosquitto/config/mosquitto.conf

# Expose Mosquitto and SSH ports
EXPOSE 1883
EXPOSE 22
EXPOSE 5201

# Generate SSH host keys, set root password, and configure SSH
RUN ssh-keygen -A \
    && echo 'root:password' | chpasswd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Use a script to run both sshd and mosquitto
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Run the custom script that starts both SSH and Mosquitto
CMD ["/run.sh"]



# Command to run Mosquitto
#CMD ["mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
