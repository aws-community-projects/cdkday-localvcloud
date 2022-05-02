import { Stack, StackProps } from 'aws-cdk-lib';
import { AttributeType, Table } from 'aws-cdk-lib/aws-dynamodb';
import { LogGroup } from 'aws-cdk-lib/aws-logs';
import {
  Choice,
  Condition,
  JsonPath,
  LogLevel,
  Pass,
  StateMachine,
} from 'aws-cdk-lib/aws-stepfunctions';
import {
  DynamoAttributeValue,
  DynamoGetItem,
} from 'aws-cdk-lib/aws-stepfunctions-tasks';
import { Construct } from 'constructs';

export class CdkdayLocalvcloudStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const table = new Table(this, 'DrivingAgeTable', {
      partitionKey: { name: 'pk', type: AttributeType.STRING },
      tableName: 'DrivingAge',
    });

    const getItem = new DynamoGetItem(this, 'GetByCountry', {
      key: {
        pk: DynamoAttributeValue.fromString(JsonPath.stringAt('$.Country')),
      },
      resultPath: '$.Result',
      table,
    });

    const oldEnough = new Choice(this, 'Can you drive?');

    const canDrive = new Pass(this, 'Can Drive');

    const cannotDrive = new Pass(this, 'Cannot Drive');

    /**
     * WARNING! THIS DOES NOT WORK!
     * DynamoDB always returns string values and ASL sadly can't convert.
     * This comparison will end up being 16 > "16" and will always be true.
     *
     * To fix this, we need to introduce a Lambda function instead of the direct DynamoDB integration.
     * Alternately, we could pivot to a different app that doesn't need to get numbers from DynamoDB.
     */
    oldEnough.when(
      Condition.numberGreaterThanEqualsJsonPath('$.Age', '$.Result.Item.Age.N'),
      canDrive
    );

    oldEnough.when(
      Condition.numberLessThanJsonPath('$.Age', '$.Result.Item.Age.N'),
      cannotDrive
    );

    new StateMachine(this, 'DrivingAgeStateMachine', {
      definition: getItem.next(oldEnough),
      logs: {
        destination: new LogGroup(this, 'DrivingAgeStateMachineLogs'),
        includeExecutionData: true,
        level: LogLevel.ALL,
      },
      stateMachineName: 'DrivingAgeStateMachine',
    });
  }
}
