#!/bin/bash
#
# Install Docker Universal Control Plane on Ubuntu

# UCP URL
readonly UCP_URL=$1

# External Service Load Balancer URL
readonly APPS_LB_URL=$2

# Is node a worker or manager?
readonly NODE_ROLE=$3

# Version of UCP to be installed
readonly UCP_VERSION="3.0.0-beta3"

# UCP Administrator Credentials
readonly UCP_ADMIN="admin"
readonly UCP_PASSWORD="Docker123!"

# Install jq library for parsing JSON
sudo apt-get -qq install jq -y

checkUCP() {

    # Check if UCP exists by attempting to hit its load balancer
    STATUS=$(curl --request GET --url "https://${UCP_URL}" --insecure --silent --output /dev/null -w '%{http_code}' --max-time 5)
    
    if [ "$STATUS" -eq 200 ]; then
        echo "checkUCP: Successfully queried the UCP API. UCP is installed. Joining node to existing cluster."
        joinUCP
    else
        echo "checkUCP: Failed to query the UCP API. UCP is not installed. Installing UCP."
        installUCP
    fi

}

installUCP() {
    
    echo "installUCP: Installing Docker Universal Control Plane (UCP)"

    # Install Universal Control Plane
    docker run \
        --rm \
        --name ucp \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        docker/ucp:"${UCP_VERSION}" install \
        --admin-username "${UCP_ADMIN}" \
        --admin-password "${UCP_PASSWORD}" \
        --san "${UCP_URL}" \
        --external-service-lb "${APPS_LB_URL}"

    echo "installUCP: Finished installing Docker Universal Control Plane (UCP)"

}

joinUCP() {

    # Get Authentication Token
    AUTH_TOKEN=$(curl --request POST --url "https://${UCP_URL}/auth/login" --insecure --silent --header 'Accept: application/json' --data '{ "username": "'${UCP_ADMIN}'", "password": "'${UCP_PASSWORD}'" }' | jq --raw-output .auth_token)

    # Get Swarm Manager IP Address + Port
    UCP_MANAGER_ADDRESS=$(curl --request GET --url "https://${UCP_URL}/info" --insecure --silent --header 'Accept: application/json' --header "Authorization: Bearer ${AUTH_TOKEN}" | jq --raw-output .Swarm.RemoteManagers[0].Addr)
    
    # Get Swarm Join Tokens
    UCP_JOIN_TOKENS=$(curl --request GET --url "https://${UCP_URL}/swarm" --insecure --silent --header 'Accept: application/json' --header "Authorization: Bearer ${AUTH_TOKEN}" | jq .JoinTokens)
    UCP_JOIN_TOKEN_MANAGER=$(echo "${UCP_JOIN_TOKENS}" | jq --raw-output .Manager)
    UCP_JOIN_TOKEN_WORKER=$(echo "${UCP_JOIN_TOKENS}" | jq --raw-output .Worker)

    # Join Swarm
    if [ "$NODE_ROLE" = "Manager" ]
    then
        echo "joinUCP: Joining Swarm as a Manager"
        docker swarm join --token "${UCP_JOIN_TOKEN_MANAGER}" "${UCP_MANAGER_ADDRESS}"
    else
        echo "joinUCP: Joining Swarm as a Worker"
        docker swarm join --token "${UCP_JOIN_TOKEN_WORKER}" "${UCP_MANAGER_ADDRESS}"
    fi

    echo "joinUCP: Finished joining node to UCP"

}

main() {
  checkUCP
}

main