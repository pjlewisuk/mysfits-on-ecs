#! /bin/bash

set -eu

if [[ $# -eq 1 ]]; then
  STACK_NAME=$1
else
  STACK_NAME="mysfits"
fi

echo "Fetching CloudFormation outputs..."
script/fetch-outputs.sh ${STACK_NAME}

echo "Populating DynamoDB table..."
script/load-ddb.sh

echo "Uploading static site to S3..."
script/upload-site.sh

echo "Success!"