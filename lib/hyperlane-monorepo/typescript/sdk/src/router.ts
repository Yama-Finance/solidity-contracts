import type { ethers } from 'ethers';

import { Router } from '@hyperlane-xyz/core';
import type { types } from '@hyperlane-xyz/utils';

import { HyperlaneContracts, HyperlaneFactories } from './contracts';

export type RouterContracts<RouterContract extends Router = Router> =
  HyperlaneContracts & {
    router: RouterContract;
  };

type RouterFactory<RouterContract extends Router = Router> =
  ethers.ContractFactory & {
    deploy: (...args: any[]) => Promise<RouterContract>;
  };

export type RouterFactories<RouterContract extends Router = Router> =
  HyperlaneFactories & {
    router: RouterFactory<RouterContract>;
  };

export type ConnectionClientConfig = {
  mailbox: types.Address;
  interchainGasPaymaster: types.Address;
  interchainSecurityModule?: types.Address;
};

export { Router } from '@hyperlane-xyz/core';
