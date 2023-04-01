import {
  CircleBridgeAdapter,
  CircleBridgeAdapter__factory,
  InterchainAccountRouter,
  InterchainAccountRouter__factory,
  InterchainQueryRouter,
  InterchainQueryRouter__factory,
  LiquidityLayerRouter,
  LiquidityLayerRouter__factory,
  PortalAdapter,
  PortalAdapter__factory,
} from '@hyperlane-xyz/core';

import { RouterContracts, RouterFactories } from './router';

export type InterchainAccountFactories =
  RouterFactories<InterchainAccountRouter>;

export const interchainAccountFactories: InterchainAccountFactories = {
  router: new InterchainAccountRouter__factory(),
};

export type InterchainAccountContracts =
  RouterContracts<InterchainAccountRouter>;

export type InterchainQueryFactories = RouterFactories<InterchainQueryRouter>;

export const interchainQueryFactories: InterchainQueryFactories = {
  router: new InterchainQueryRouter__factory(),
};

export type InterchainQueryContracts = RouterContracts<InterchainQueryRouter>;

export type LiquidityLayerFactories = RouterFactories<LiquidityLayerRouter> & {
  circleBridgeAdapter: CircleBridgeAdapter__factory;
  portalAdapter: PortalAdapter__factory;
};

export const liquidityLayerFactories: LiquidityLayerFactories = {
  router: new LiquidityLayerRouter__factory(),
  circleBridgeAdapter: new CircleBridgeAdapter__factory(),
  portalAdapter: new PortalAdapter__factory(),
};

export type LiquidityLayerContracts = RouterContracts<LiquidityLayerRouter> & {
  circleBridgeAdapter?: CircleBridgeAdapter;
  portalAdapter?: PortalAdapter;
};
