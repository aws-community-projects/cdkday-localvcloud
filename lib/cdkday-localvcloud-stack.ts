import { Stack, StackProps } from 'aws-cdk-lib';
import { AttributeType, Table } from 'aws-cdk-lib/aws-dynamodb';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { LogGroup } from 'aws-cdk-lib/aws-logs';
import {
  Choice,
  Condition,
  LogLevel,
  Pass,
  StateMachine,
} from 'aws-cdk-lib/aws-stepfunctions';
import { LambdaInvoke } from 'aws-cdk-lib/aws-stepfunctions-tasks';
import { Construct } from 'constructs';

export class CdkdayLocalvcloudStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const table = new Table(this, 'DrivingAgeTable', {
      partitionKey: { name: 'pk', type: AttributeType.STRING },
      tableName: 'DrivingAge',
    });

    const fn = new NodejsFunction(this, 'CheckAgeFn', {
      environment: { TABLE_NAME: table.tableName },
      entry: 'lib/check-age.ts',
      functionName: 'CheckAgeFn',
    });

    table.grantReadData(fn);

    // const getItem = new DynamoGetItem(this, 'GetByCountry', {
    //   key: {
    //     pk: DynamoAttributeValue.fromString(JsonPath.stringAt('$.Country')),
    //   },
    //   resultPath: '$.Result',
    //   table,
    // });

    const checkAge = new LambdaInvoke(this, 'CheckAge', {
      lambdaFunction: fn,
      resultPath: '$.Result',
    });

    const oldEnough = new Choice(this, 'Can you drive?');

    const canDrive = new Pass(this, 'Can Drive');

    const cannotDrive = new Pass(this, 'Cannot Drive');

    oldEnough.when(
      Condition.numberGreaterThanEqualsJsonPath('$.Age', '$.Result.Payload'),
      canDrive
    );

    oldEnough.otherwise(cannotDrive);

    new StateMachine(this, 'DrivingAgeStateMachine', {
      definition: checkAge.next(oldEnough),
      logs: {
        destination: new LogGroup(this, 'DrivingAgeStateMachineLogs'),
        includeExecutionData: true,
        level: LogLevel.ALL,
      },
      stateMachineName: 'DrivingAgeStateMachine',
    });
  }
}
