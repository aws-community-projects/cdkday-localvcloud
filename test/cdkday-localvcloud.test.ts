import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { expect, test } from 'vitest';

import * as CdkdayLocalvcloud from '../lib/cdkday-localvcloud-stack';

test('Create Stack', () => {
  const app = new cdk.App();
  // WHEN
  const stack = new CdkdayLocalvcloud.CdkdayLocalvcloudStack(
    app,
    'MyTestStack'
  );
  // THEN
  const template = Template.fromStack(stack);

  expect(template).toMatchSnapshot();
});
