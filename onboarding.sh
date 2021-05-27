#!/bin/bash

if [ $# -ne 1 ] ; then
	echo "usage : $0 ID_APPLICATION_DOCKER"
	exit 1
fi
ID_APPLICATION_DOCKER=$1

UCP_URL=mke.pac-catfish.dockerps.io
DTR_URL=msr.pac-catfish.dockerps.io
UCP_USERNAME=admin
UCP_PASSWORD=xxx

if [ "${ID_APPLICATION_DOCKER}" = "" ] ; then
	echo "ERROR"
	exit 1
fi

# Roles given 
LDAP_GROUP="cn=devops,ou=groups,dc=test,dc=com"
ROLE_UCP="restrictedcontrol"
ROLE_DTR="admin"

AUTHTOKEN=$(curl -sk -d '{"username":"'${UCP_USERNAME}'","password":"'${UCP_PASSWORD}'"}' https://${UCP_URL}/auth/login | jq -r .auth_token)
echo $AUTHTOKEN
[[ "${AUTHTOKEN}" = "null" ]] && echo "Invalid token. Verify username/password" && exit 1


function api_docker_get {
	API=$*
	curl -sk -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_URL}${API}
}
function api_docker_post {
	API=$*
	curl -sk -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_URL}${API}
}
function api_docker_put {
	API=$*
	curl -sk -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_URL}${API}
}
function api_docker_del {
	API=$*
	curl -sk -X DELETE -H 'Accept: application/json' -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_URL}${API}
}

function create_organization {
	ORGANIZATION=$1
	api_docker_post /accounts/ -d '{"name":"'${ORGANIZATION}'","isOrg":true}'
}

function create_collection {
	COLLECTION=$1
	api_docker_post /collections -d '{"name":"'${COLLECTION}'","path":"/","parent_id":"shared"}'
}

function create_network {
	NETWORK=$1
	COLLECTION=$2
	api_docker_post /networks/create -d '{"name":"'${NETWORK}'","Driver":"overlay","labels":{"com.docker.ucp.access.label":"'/Shared/${COLLECTION}'"}}'
}

function get_collection_id {
	COLLECTION=$1
	api_docker_get /collectionByPath?path=%2FShared%2F${COLLECTION} | jq -r .id
}

function get_team_id {
	ORGANIZATION=$1
	TEAM=$2
	api_docker_get /accounts/${ORGANIZATION}/teams/${TEAM} | jq -r .id
}

function create_grant {
	TEAM_ID=$1
	ROLE=$2
	COLLECTION_ID=$3
	api_docker_put /collectionGrants/${TEAM_ID}/${COLLECTION_ID}/${ROLE}
}

function create_team {
	ORGANIZATION=$1
	TEAM=$2
	GROUP_DN=$3
	api_docker_post /accounts/${ORGANIZATION}/teams -d '{"name":"'${TEAM}'","description":"'${TEAM}'"}'
	api_docker_put /accounts/${ORGANIZATION}/teams/${TEAM}/memberSyncConfig -d '{"enableSync":true,"groupDN":"'${GROUP_DN}'","groupMemberAttr":"uniqueMember","searchBaseDN":"","searchFilter":"","searchScopeSubtree":false,"selectGroupMembers":true}'
}

function create_dtr_grant {
	TEAM=$1
	ROLE=$2
	ORGANIZATION=$3
	curl -k -u ${UCP_USERNAME}:${UCP_PASSWORD} -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' https://${DTR_URL}/api/v0/repositoryNamespaces/${ORGANIZATION}/teamAccess/${TEAM}  -d '{ "accessLevel": "'${ROLE}'"}'
}


echo 
echo "################################################################"
echo "##### ORGANIZATION / TEAMS #######"
echo "################################################################"
echo "Creating UCP Organization..."
ORGANIZATION_NAME=${ID_APPLICATION_DOCKER}

echo "Organisation=${ORGANIZATION_NAME}"


echo "DEBUG : del org"
api_docker_del /accounts/${ORGANIZATION_NAME}

echo "#create_organization ${ORGANIZATION_NAME}"
create_organization ${ORGANIZATION_NAME}

COLLECTION_NAME=${ORGANIZATION_NAME}
echo 
echo "#### Creating Collection ${COLLECTION_NAME}... ####"
echo "#create_collection ${COLLECTION_NAME}"
create_collection ${COLLECTION_NAME}

NETWORK_NAME=${ORGANIZATION_NAME}
echo 
echo "#### Creating Network ${NETWORK_NAME} in collection /Shared/${COLLECTION_NAME}... ####"
echo "#create_network ${NETWORK_NAME} ${COLLECTION_NAME}"
create_network ${NETWORK_NAME} ${COLLECTION_NAME}

TEAM_NAME=${ORGANIZATION_NAME}-RW
echo 
echo "#### Creating UCP Team ${ORGANIZATION_NAME}/${TEAM_NAME}... ####"
echo "#create_team ${ORGANIZATION_NAME} ${TEAM_NAME} ${LDAP_GROUP}"
create_team ${ORGANIZATION_NAME} ${TEAM_NAME} "cn=devops,ou=groups,dc=test,dc=com"

echo
echo
echo "#### Trigger ldap sync... ####"
api_docker_post /enzi/v0/jobs -d '{"action":"ldap-sync"}'

COLLECTION_ID=$(get_collection_id ${COLLECTION_NAME})
TEAM_ID=$(get_team_id ${ORGANIZATION_NAME} ${TEAM_NAME})
echo 
echo "#### Creating UCP Grant - Role ${ROLE_UCP} on /Shared/${COLLECTION_NAME} to ${TEAM_NAME}... ####"
echo "#create_grant ${TEAM_ID} ${ROLE_UCP} ${COLLECTION_ID}"
create_grant ${TEAM_ID} ${ROLE_UCP} ${COLLECTION_ID}

echo
echo
echo "#### Creating DTR Grant - ${ROLE_DTR} on ${ORGANIZATION_NAME} to ${TEAM_NAME}... ####"
echo "#create_dtr_grant ${TEAM_NAME} ${ROLE_DTR} ${ORGANIZATION_NAME}"
create_dtr_grant ${TEAM_NAME} ${ROLE_DTR} ${ORGANIZATION_NAME}
