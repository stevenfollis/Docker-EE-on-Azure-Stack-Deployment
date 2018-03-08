#!/bin/bash
#
# Install Docker Enterprise Edition Engine on Ubuntu

# Store license URL
readonly DOCKER_EE_URL=$1

# Filename of tar'd UCP Images
readonly UCP_IMAGES_FILE=$2

# UCP URL
readonly UCP_URL=$3

# Repository name for Docker EE Engine
readonly DOCKER_EE_VERSION="test"

# Version of UCP to be installed
readonly UCP_VERSION="3.0.0-beta3"

# Version of DTR to be installed
readonly DTR_VERSION="latest"

# CIDR of the subnet containing cluster nodes
readonly AZURE_SUBNET_CIDR="10.0.0.0/24"

installEngine() {

  # Update the apt package index
  sudo apt-get -qq update

  # Install packages to allow apt to use a repository over HTTPS
  sudo apt-get -qq install \
    apt-transport-https \
    curl \
    software-properties-common

  # Add Docker’s official GPG key using your customer Docker EE repository URL
  curl -fsSL "$DOCKER_EE_URL"/ubuntu/gpg | sudo apt-key add -

  # Set up the Docker repository
  sudo add-apt-repository \
    "deb [arch=amd64] ${DOCKER_EE_URL}/ubuntu \
    $(lsb_release -cs) \
    $DOCKER_EE_VERSION"

  # Update the apt package index
  sudo apt-get -qq update

  # Install the latest version of Docker EE
  # dpkg produces lots of chatter
  # redirect to abyss via https://askubuntu.com/a/258226
  sudo apt-get -qq install docker-ee > /dev/null

  # Finished
  echo "Finished installing Docker EE Engine"

}

loadImages() {

  if [ -z "$UCP_IMAGES_FILE" ]
  then
    echo "No UCP Images file specified. Skipping load."
  else
    echo "Loading UCP images"
    docker load < "./${UCP_IMAGES_FILE}"
    echo "Finished loading UCP Images"
  fi
  
}

configure_swarm() {

  # Initiate a Docker Swarm
  docker swarm init

  # Create secret from toml file
  docker secret create azure_ucp_admin.toml "./azure_ucp_admin.toml"

  # Use secret in a service to prepopulate VMs with IPs
  docker service create \
    --mode=global \
    --secret=azure_ucp_admin.toml \
    --log-driver json-file \
    --log-opt max-size=1m \
    --name ipallocator \
    ddebroy/azip

}

installUCP() {
    
    echo "Installing Docker Universal Control Plane (UCP)"

    # Install Universal Control Plane
    # Uses port 8080 to avoid conflict with DTR
    docker run \
        --rm \
        --name ucp \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        docker/ucp:"${UCP_VERSION}" install \
        --admin-username "admin" \
        --admin-password "Docker123!" \
        --san "${UCP_URL}" \
        --controller-port 8080 
        #--cloud-provider Azure \
        #--pod-cidr "${AZURE_SUBNET_CIDR}"

    echo "Finished installing Docker Universal Control Plane (UCP)"

}

installDTR() {

    echo "Installing Docker Trusted Registry (DTR)"

    # Install Docker Trusted Registry
    # Uses port 443 for ease of pulls/pushes
    docker run \
        --rm \
        docker/dtr:latest install \
        --dtr-external-url "${UCP_URL}" \
        --ucp-node manager01 \
        --ucp-username "admin" \
        --ucp-password "Docker123!" \
        --ucp-url "${UCP_URL}":8080 \
        --ucp-insecure-tls 

    echo "Finished installing Docker Trusted Registry (DTR)"

}

main() {
  installEngine
  loadImages
  #configure_swarm
  installUCP
  installDTR
}

main