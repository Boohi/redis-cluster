#!/bin/bash
STARTING_PORT=7000

# Number of nodes to create. Should be an even number
NUM_OF_NODES=6

# Add your own auth key, imported from .env file
. ./.env
AUTH=$MASTERPASS

# Get IP Address of the server
IP=$(hostname -I | grep -o "^[0-9.]*")

# RedisJSON module location
REDISJSON_MODULE=/home/boohi/RedisJSON/target/release/librejson.so

function create_node_folders {
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		sudo mkdir -p /etc/redis/cluster/node-$port
	done
}

function create_config_files {
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		{
			echo "port $port"
			echo "dir /var/lib/redis/$port/"
			echo "appendonly no"
			echo "protected-mode no"
			echo "cluster-enabled yes"
			echo "cluster-node-timeout 5000"
			echo "cluster-config-file /etc/redis/cluster/node-$port/nodes_$port.conf"
			echo "pidfile /var/run/redis/redis_$port.pid"
			echo "logfile /var/log/redis/redis_$port.log"
			echo "loglevel notice"
			echo "requirepass $AUTH"
			echo "masterauth $AUTH"
			echo "loadmodule $REDISJSON_MODULE"

		} >> /etc/redis/cluster/node-$port/redis-$port.conf
		sudo mkdir -p /var/lib/redis/$port
	done
	sudo chown redis:redis -R /var/lib/redis
	sudo chmod 770 -R /var/lib/redis
	sudo chown redis:redis -R /etc/redis
}

function create_service_files {
	# The above is a template, use it to create the actual service files
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		TARGET_DIR=/etc/systemd/system/redis_$port.service
		{
			echo "[Unit]"
			echo "Description=Redis key-value database on $port"
			echo "After=network.target"

			echo "[Service]"
			echo "ExecStart=/usr/bin/redis-server /etc/redis/cluster/node-$port/redis-$port.conf --supervised systemd"
			echo "ExecStop=/bin/redis-cli -h 127.0.0.1 -p $port shutdown"
			echo "Type=notify"
			echo "User=redis"
			echo "Group=redis"
			echo "RuntimeDirectory=redis"
			echo "RuntimeDirectoryMode=0755"
			echo "LimitNOFILE=65535"

			echo "[Install]"
			echo "WantedBy=multi-user.target"
		} >> $TARGET_DIR
		
	done
}

function start_services {
	sudo systemctl daemon-reload
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		sudo systemctl start redis_$port.service
		sudo systemctl enable redis_$port.service
	done
}

function start_cluster {
	command="redis-cli --cluster create"
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		command+=" $IP:$port"
	done
	command+=" --cluster-replicas 1 -a '$AUTH'"
	eval "$command"
	echo "Cluster started"
}

function clean {
	sudo rm -rf /etc/redis/cluster
	sudo rm -rf /var/lib/Redis
	sudo rm -rf /etc/systemd/system/redis_70*.service
	# Disable all services
	for ((i=0; i<NUM_OF_NODES; i++)); do
		port=$((STARTING_PORT + i))
		sudo systemctl stop redis_$port.service
		sudo systemctl disable redis_$port.service
	done
	sudo systemctl daemon-reload
	echo "Cleaned up"
}

case $1 in
	create)
		clean
		create_node_folders
		create_config_files
		create_service_files
		;;
	start)
		start_services
		start_cluster
		;;
	delete)
		clean
		;;
	clean)
		clean
		;;
	*)
		echo "Usage: $0 {create|start|delete|clean}"
		exit 1
		;;
esac