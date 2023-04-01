import { chainMetadata } from './consts/chainMetadata';
import { AllChains } from './consts/chains';
import { ChainName, LooseChainMap } from './types';

export const DomainIdToChainName = Object.fromEntries(
  AllChains.map((chain) => {
    if (!chainMetadata[chain])
      throw new Error(`Chain metadata for ${chain} could not be found`);
    return [chainMetadata[chain].id, chain];
  }),
) as Record<number, ChainName>;

export const ChainNameToDomainId = Object.fromEntries(
  AllChains.map((chain) => [chain, chainMetadata[chain].id]),
) as LooseChainMap<number>;
