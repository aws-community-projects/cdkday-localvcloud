import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';

interface InputEvent {
  Country: string;
}

const { AWS_SAM_LOCAL, TABLE_NAME } = process.env;

const docClient = DynamoDBDocumentClient.from(
  new DynamoDBClient({
    endpoint: AWS_SAM_LOCAL ? 'http://ddb:8000' : '',
  })
);

export const handler = async (event: InputEvent): Promise<number> => {
  const { Country } = event;
  const command = new GetCommand({
    Key: { pk: Country },
    TableName: TABLE_NAME,
  });
  const response = await docClient.send(command);
  if (response.Item) {
    return response.Item.Age;
  }
  throw new Error(`Country ${Country} not found!`);
};
