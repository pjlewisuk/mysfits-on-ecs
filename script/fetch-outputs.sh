#! /bin/bash

set -eu

if [[ $# -eq 1 ]]; then
  STACK_NAME=$1
else
  STACK_NAME="mysfits"
fi

aws cloudformation describe-stacks --stack-name "$STACK_NAME" --output json | jq -r '[.Stacks[0].Outputs[] | {key: .OutputKey, value: .OutputValue}] | from_entries' > cfn-output.json
