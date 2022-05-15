#!/bin/bash
set -euo pipefail

AGE="${1:-16}"
COUNTRY="${2:-USA}"
SAMPID=""

# Remove containers and kill SAM process
function cleanup {
    # Stop the DynamoDB and Step Functions services.
    docker stop ddb sfn || true

    # Remove the Docker network.
    docker network remove cdkday || true

    # Stop the SAM process.
    kill $SAMPID
}

# Called multiple times so abstracted into a function
function get_execution_history {
    aws stepfunctions get-execution-history \
        --endpoint http://localhost:8083 \
        --no-cli-pager \
        --execution-arn $EXECUTION_ARN
}

# Remove containers and network on exit.
trap cleanup ERR EXIT SIGINT SIGTERM

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

# Start DynamoDB Service in Docker.
docker run -d --name ddb --network cdkday -p 8000:8000 --rm amazon/dynamodb-local:latest

# Create the table using the generated name from the cloud assembly.
# Even though the table is named in CDK, SAM can only find the table REF.
aws dynamodb create-table \
    --table-name DrivingAgeTable8E413A64 \
    --attribute-definitions AttributeName=pk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url http://localhost:8000 \
    --no-cli-pager \
    --region us-east-1

# Add the items in `request-items.json` to the DynamoDB table.
aws dynamodb batch-write-item \
    --request-items file://request-items.json \
    --endpoint-url http://localhost:8000 \
    --no-cli-pager \
    --region us-east-1

# Start Step Functions service in Docker configured to use the SAM endpoint for Lambda.
docker run -d --name sfn --network cdkday -p 8083:8083 --rm \
    --mount type=bind,readonly,source=$PWD/mock-configuration.json,destination=/home/StepFunctionsLocal/MockConfigFile.json \
    -e LAMBDA_ENDPOINT=http://host.docker.internal:3001 \
    -e SFN_MOCK_CONFIG="/home/StepFunctionsLocal/MockConfigFile.json" \
    amazon/aws-stepfunctions-local

# Create the state machine with our generated ASL definition file.
until aws stepfunctions create-state-machine \
    --endpoint-url http://localhost:8083 \
    --definition file://$PWD/asl-0.json \
    --name "LocalTesting" \
    --no-cli-pager \
    --role-arn "arn:aws:iam::123456789012:role/DummyRole"; do
    sleep 1
done

# Start the state machine, passing in the Age and Country values.
EXECUTION_ARN=$(aws stepfunctions start-execution \
    --endpoint http://localhost:8083 \
    --no-cli-pager \
    --state-machine arn:aws:states:us-east-1:123456789012:stateMachine:LocalTesting#HappyPathTest \
    --input "{\"Age\": $AGE, \"Country\" : \"$COUNTRY\"}" |
    jq -r '.executionArn')

# Poll the state machine until `ExecutionSucceeded` is seen.
max_retry=5
counter=0
until get_execution_history | grep -q "ExecutionSucceeded"; do
    sleep 1
    [[ counter -eq $max_retry ]] && get_execution_history && exit 1
    ((counter++))
done

# See the state machine execution logs.
get_execution_history
