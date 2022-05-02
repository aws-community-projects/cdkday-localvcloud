#!/bin/bash
set -euo pipefail

npx cdk synth

npx cdk-asl-extractor cdk.out/CdkdayLocalvcloudStack.template.json

docker run -d --name sfn -p 8083:8083 --rm --mount type=bind,readonly,source=$PWD/mock-configuration.json,destination=/home/StepFunctionsLocal/MockConfigFile.json \
    -e SFN_MOCK_CONFIG="/home/StepFunctionsLocal/MockConfigFile.json" amazon/aws-stepfunctions-local

aws stepfunctions create-state-machine \
    --endpoint-url http://localhost:8083 \
    --definition file://$PWD/asl-0.json \
    --name "LocalTesting" \
    --no-cli-pager \
    --role-arn "arn:aws:iam::123456789012:role/DummyRole"

aws stepfunctions start-execution \
    --endpoint http://localhost:8083 \
    --no-cli-pager \
    --state-machine arn:aws:states:us-east-1:123456789012:stateMachine:LocalTesting#HappyPathTest \
    --input "{\"Age\": 16, \"Country\" : \"USA\"}"

docker logs sfn

docker stop sfn
