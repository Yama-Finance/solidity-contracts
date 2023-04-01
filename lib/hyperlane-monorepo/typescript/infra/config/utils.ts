import { ChainMap, ChainName, chainMetadata } from '@hyperlane-xyz/sdk';

import { HelloWorldConfig } from '../src/config';
import { MatchingList } from '../src/config/agent';

import { Contexts } from './contexts';

export const MATCHING_LIST_ALL_WILDCARDS = [
  {
    originDomain: '*',
    senderAddress: '*',
    destinationDomain: '*',
    recipientAddress: '*',
  },
];

export function helloworldMatchingList<Chain extends ChainName>(
  helloWorldConfigs: Partial<Record<Contexts, HelloWorldConfig<Chain>>>,
  context: Contexts,
) {
  const helloWorldConfig = helloWorldConfigs[context];
  if (!helloWorldConfig) {
    throw Error(`No HelloWorldConfig found for context ${context}`);
  }
  return routerMatchingList(helloWorldConfig.addresses);
}

export function routerMatchingList<Chain extends ChainName>(
  routers: ChainMap<Chain, { router: string }>,
) {
  const chains = Object.keys(routers) as Chain[];

  const matchingList: MatchingList = [];

  for (const source of chains) {
    for (const destination of chains) {
      if (source === destination) {
        continue;
      }

      matchingList.push({
        originDomain: chainMetadata[source].id,
        senderAddress: routers[source].router,
        destinationDomain: chainMetadata[destination].id,
        recipientAddress: routers[destination].router,
      });
    }
  }
  return matchingList;
}
