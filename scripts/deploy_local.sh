#!/bin/bash

if [ "$1" = "" ]
then
  echo "Usage: $0 1 arg required - juno address"
  exit
fi

# pinched and adapted from DA0DA0
# this rather assumes you're using juno bootstrap script
# this script takes an address to use inside the container
# you get this address when running the juno bootstrap - it will be logged
IMAGE_TAG="v2.0.4"
CONTAINER_NAME="juno_whoami"
BINARY="docker exec -i $CONTAINER_NAME junod"
DENOM='ujunox'
CHAIN_ID='testing'
RPC='http://localhost:26657/'
TXFLAG="--gas-prices 0.01$DENOM --gas auto --gas-adjustment 1.3 -y -b block --chain-id $CHAIN_ID --node $RPC"

# kill any orphans
docker kill $CONTAINER_NAME
docker volume rm -f junod_data

# run junod setup script
docker run --rm -it \
    -e PASSWORD=xxxxxxxxx \
    -e STAKE_TOKEN=$DENOM \
    --mount type=volume,source=junod_data,target=/root \
    ghcr.io/cosmoscontracts/juno:$IMAGE_TAG /opt/setup_junod.sh $1

# we need app.toml and config.toml to enable CORS
# this means some wrangling required
docker run -v junod_data:/root --name helper busybox true
docker cp docker/app.toml helper:/root/.juno/config/app.toml
docker cp docker/config.toml helper:/root/.juno/config/config.toml
docker rm helper

docker run --rm -d --name $CONTAINER_NAME \
    -p 1317:1317 -p 26656:26656 -p 26657:26657 \
    --mount type=volume,source=junod_data,target=/root \
    ghcr.io/cosmoscontracts/juno:$IMAGE_TAG ./run_junod.sh

# compile
docker run --rm -v "$(pwd)":/code \
  --mount type=volume,source="$(basename "$(pwd)")_cache",target=/code/target \
  --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
  cosmwasm/rust-optimizer:0.12.3

# copy wasm to docker container
docker cp artifacts/whoami.wasm $CONTAINER_NAME:/whoami.wasm

# you ideally want to run locally, get a user and then
# pass that addr in here
echo "Address to deploy contracts: $1"
echo "TX Flags: $TXFLAG"

# upload whoami wasm
CONTRACT_CODE=$($BINARY tx wasm store "/whoami.wasm" --from validator $TXFLAG --output json | jq -r '.logs[0].events[-1].attributes[0].value')

echo "Stored: $CONTRACT_CODE"

# instantiate the CW721
WHOAMI_INIT='{
  "minter": "'"$1"'",
  "name": "Whoami Juno Name Service",
  "symbol": "WHO"
}'
echo "$WHOAMI_INIT"
$BINARY tx wasm instantiate $CONTRACT_CODE "$WHOAMI_INIT" --from "validator" --label "whoami NFT nameservice" $TXFLAG

# get contract addr
CONTRACT_ADDRESS=$($BINARY q wasm list-contract-by-code $CONTRACT_CODE --output json | jq -r '.contracts[-1]')

# Print out config variables
printf "\n ------------------------ \n"
printf "Config Variables \n\n"

echo "WHOAMI_CODE_ID=$CONTRACT_CODE"
echo "WHOAMI_ADDRESS=$CONTRACT_ADDRESS"
