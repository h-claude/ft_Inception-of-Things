#!/bin/bash

#ufw allow 6443/tcp #apiserver
#ufw allow from 10.42.0.0/16 to any #pods
#ufw allow from 10.43.0.0/16 to any #services

echo "Installing K3s Server..."

export K3S_KUBECONFIG_MODE="644"
export INSTALL_K3S_EXEC="server --node-external-ip=192.168.56.110 --bind-address=192.168.56.110"

curl -sfL https://get.k3s.io | sh -
if [ $? -ne 0 ]; then
	echo "Failed to install k3s. Exiting."
	exit 1
fi

