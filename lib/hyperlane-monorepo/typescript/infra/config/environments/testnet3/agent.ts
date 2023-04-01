import { chainMetadata } from '@hyperlane-xyz/sdk';

import { ALL_KEY_ROLES, KEY_ROLE_ENUM } from '../../../src/agents/roles';
import { AgentConfig } from '../../../src/config';
import {
  ConnectionType,
  GasPaymentEnforcementPolicyType,
} from '../../../src/config/agent';
import { Contexts } from '../../contexts';
import { helloworldMatchingList, routerMatchingList } from '../../utils';

import { TestnetChains, chainNames, environment } from './chains';
import { helloWorld } from './helloworld';
import interchainQueryRouters from './middleware/queries/addresses.json';
import { validators } from './validators';

const releaseCandidateHelloworldMatchingList = helloworldMatchingList(
  helloWorld,
  Contexts.ReleaseCandidate,
);

const interchainQueriesMatchingList = routerMatchingList(
  interchainQueryRouters,
);

export const hyperlane: AgentConfig<TestnetChains> = {
  environment,
  namespace: environment,
  runEnv: environment,
  context: Contexts.Hyperlane,
  docker: {
    repo: 'gcr.io/abacus-labs-dev/hyperlane-agent',
    // commit date: 2023-02-07
    tag: 'b55d7c5-20230207-165646',
  },
  aws: {
    region: 'us-east-1',
  },
  environmentChainNames: chainNames,
  contextChainNames: chainNames,
  validatorSets: validators,
  gelato: {
    enabledChains: [],
  },
  connectionType: ConnectionType.HttpFallback,
  validator: {
    default: {
      interval: 5,
      reorgPeriod: 1,
    },
    chainOverrides: {
      alfajores: {
        reorgPeriod: chainMetadata.alfajores.blocks.reorgPeriod,
      },
      fuji: {
        reorgPeriod: chainMetadata.fuji.blocks.reorgPeriod,
      },
      mumbai: {
        reorgPeriod: chainMetadata.mumbai.blocks.reorgPeriod,
      },
      bsctestnet: {
        reorgPeriod: chainMetadata.bsctestnet.blocks.reorgPeriod,
      },
      goerli: {
        reorgPeriod: chainMetadata.goerli.blocks.reorgPeriod,
      },
      moonbasealpha: {
        reorgPeriod: chainMetadata.moonbasealpha.blocks.reorgPeriod,
      },
    },
  },
  relayer: {
    default: {
      blacklist: [
        ...releaseCandidateHelloworldMatchingList,
        { recipientAddress: '0xBC3cFeca7Df5A45d61BC60E7898E63670e1654aE' },
      ],
      gasPaymentEnforcement: {
        policy: {
          type: GasPaymentEnforcementPolicyType.Minimum,
          payment: 1,
        },
        // To continue relaying interchain query callbacks, we whitelist
        // all messages between interchain query routers.
        // This whitelist will become more strict with
        // https://github.com/hyperlane-xyz/hyperlane-monorepo/issues/1605
        whitelist: interchainQueriesMatchingList,
      },
    },
  },
  rolesWithKeys: ALL_KEY_ROLES,
};

export const releaseCandidate: AgentConfig<TestnetChains> = {
  environment,
  namespace: environment,
  runEnv: environment,
  context: Contexts.ReleaseCandidate,
  docker: {
    repo: 'gcr.io/abacus-labs-dev/hyperlane-agent',
    // commit date: 2023-02-07
    tag: 'b55d7c5-20230207-165646',
  },
  aws: {
    region: 'us-east-1',
  },
  environmentChainNames: chainNames,
  contextChainNames: chainNames,
  validatorSets: validators,
  gelato: {
    enabledChains: [],
  },
  connectionType: ConnectionType.HttpFallback,
  relayer: {
    default: {
      whitelist: releaseCandidateHelloworldMatchingList,
      gasPaymentEnforcement: {
        policy: {
          type: GasPaymentEnforcementPolicyType.Minimum,
          payment: 1, // require 1 wei
        },
        whitelist: interchainQueriesMatchingList,
      },
      transactionGasLimit: BigInt(750000),
      // Skipping arbitrum because the gas price estimates are inclusive of L1
      // fees which leads to wildly off predictions.
      skipTransactionGasLimitFor: [chainMetadata.arbitrumgoerli.id],
    },
  },
  rolesWithKeys: [KEY_ROLE_ENUM.Relayer, KEY_ROLE_ENUM.Kathy],
};

export const agents = {
  [Contexts.Hyperlane]: hyperlane,
  [Contexts.ReleaseCandidate]: releaseCandidate,
};
