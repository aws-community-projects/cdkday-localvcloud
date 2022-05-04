#!/bin/bash
set -euo pipefail

# Generate cloud assembly.
npx cdk synth >/dev/null

# Extract ASL from cloud assembly. It will be stored as `asl-0.json`.
npx cdk-asl-extractor cdk.out/CdkdayLocalvcloudStack.template.json

# Create a Docker network so containers can communicate.
docker network create cdkday

# Start SAM service using CDK cloud assembly and our network. Service is pushed to bg.
sam local start-lambda --docker-network cdkday -t cdk.out/CdkdayLocalvcloudStack.template.json &
echo "Starting SAM..."

# Capture the PID for the SAM process so we can kill it later.
SAMPID=$!

# Sleep :(
sleep 5

# Start DynamoDB Service in Docker.
docker run -d --name ddb --network cdkday -p 8000:8000 --rm amazon/dynamodb-local:latest

# Create the table using the generated name from the cloud assembly.
# I tried setting `tableName` in CDK but SAM didn't pick it up. :(
aws dynamodb create-table \
    --table-name DrivingAgeTable8E413A64 \
    --attribute-definitions AttributeName=pk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url http://localhost:8000 \
    --no-cli-pager \
    --region us-east-1

# Add an item to the table with the pk of "USA" and Age attribute 16.
aws dynamodb put-item \
    --table-name DrivingAgeTable8E413A64 \
    --item "{ \"pk\": { \"S\": \"USA\" }, \"Age\": { \"N\": \"16\" }}" \
    --endpoint-url http://localhost:8000 \
    --no-cli-pager \
    --region us-east-1

# Start Step Functions service in Docker configured to use the SAM endpoint for Lambda.
docker run -d --name sfn --network cdkday -p 8083:8083 --rm \
    --mount type=bind,readonly,source=$PWD/mock-configuration.json,destination=/home/StepFunctionsLocal/MockConfigFile.json \
    -e LAMBDA_ENDPOINT=http://host.docker.internal:3001 \
    -e SFN_MOCK_CONFIG="/home/StepFunctionsLocal/MockConfigFile.json" \
    amazon/aws-stepfunctions-local

# Sleep :(
sleep 2

# Create the state machine with our generated ASL definition file.
aws stepfunctions create-state-machine \
    --endpoint-url http://localhost:8083 \
    --definition file://$PWD/asl-0.json \
    --name "LocalTesting" \
    --no-cli-pager \
    --role-arn "arn:aws:iam::123456789012:role/DummyRole"

# Start the state machine, passing in the Age and Country values.
aws stepfunctions start-execution \
    --endpoint http://localhost:8083 \
    --no-cli-pager \
    --state-machine arn:aws:states:us-east-1:123456789012:stateMachine:LocalTesting#HappyPathTest \
    --input "{\"Age\": 16, \"Country\" : \"USA\"}"

# Sleep :(
sleep 5

# See the state machine execution logs.
docker logs sfn

# Stop the DynamoDB and Step Functions services.
docker stop ddb sfn

# Remove the Docker network.
docker network remove cdkday

# Stop the SAM process.
kill $SAMPID
