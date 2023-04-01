import {
  ChainNameToDomainId,
  hyperlaneCoreAddresses,
  objMap,
} from '@hyperlane-xyz/sdk';

import { CheckpointStatus, S3Validator } from '../src/agents/aws/validator';
import { CheckpointSyncerType } from '../src/config/agent';

import { getContext, getCoreEnvironmentConfig, getEnvironment } from './utils';

async function main() {
  const environment = await getEnvironment();
  const coreConfig = getCoreEnvironmentConfig(environment);
  const context = await getContext();
  const validatorSets = coreConfig.agents[context]?.validatorSets;
  if (!validatorSets)
    throw Error(`No validator sets found for ${environment}:${context}`);
  objMap(validatorSets, async (chain, validatorSet) => {
    const domainId = ChainNameToDomainId[chain];
    const mailbox = hyperlaneCoreAddresses[chain].mailbox;
    const validators = validatorSet.validators.map((validator) => {
      const checkpointSyncer = validator.checkpointSyncer;
      if (checkpointSyncer.type == CheckpointSyncerType.S3) {
        return new S3Validator(
          validator.address,
          domainId,
          mailbox,
          checkpointSyncer.bucket,
          checkpointSyncer.region,
        );
      }
      throw new Error('Cannot check non-s3 validator type');
    });
    const controlValidator = validators[0];
    for (let i = 1; i < validators.length; i++) {
      const prospectiveValidator = validators[i];
      const name = validatorSet.validators[i].name;
      try {
        const metrics = await prospectiveValidator.compare(controlValidator);
        const valid =
          metrics.filter((metric) => metric.status !== CheckpointStatus.VALID)
            .length === 0;
        if (!valid) {
          console.log(`${name} has >=1 non-valid checkpoints for ${chain}`);
          console.log(JSON.stringify(metrics, null, 2));
        } else {
          console.log(`${name} has valid checkpoints for ${chain}`);
        }
      } catch (error) {
        console.error(`Comparing validator ${name} failed:`);
        console.error(error);
        throw error;
      }
    }
  });
}

main().catch(console.error);
