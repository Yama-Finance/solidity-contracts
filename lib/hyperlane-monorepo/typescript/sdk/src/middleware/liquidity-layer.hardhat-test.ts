import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

import {
  LiquidityLayerRouter,
  MockCircleMessageTransmitter,
  MockCircleMessageTransmitter__factory,
  MockCircleTokenMessenger,
  MockCircleTokenMessenger__factory,
  MockPortalBridge,
  MockPortalBridge__factory,
  MockToken,
  MockToken__factory,
  TestLiquidityLayerMessageRecipient__factory,
} from '@hyperlane-xyz/core';
import { utils } from '@hyperlane-xyz/utils';

import { testChainConnectionConfigs } from '../consts/chainConnectionConfigs';
import { TestCoreApp } from '../core/TestCoreApp';
import { TestCoreDeployer } from '../core/TestCoreDeployer';
import { LiquidityLayerApp } from '../deploy/middleware/LiquidityLayerApp';
import {
  BridgeAdapterType,
  CircleBridgeAdapterConfig,
  LiquidityLayerConfig,
  LiquidityLayerDeployer,
  PortalAdapterConfig,
} from '../deploy/middleware/LiquidityLayerRouterDeployer';
import { getChainToOwnerMap, getTestMultiProvider } from '../deploy/utils';
import { ChainNameToDomainId } from '../domains';
import { MultiProvider } from '../providers/MultiProvider';
import { ChainMap, TestChainNames } from '../types';
import { objMap } from '../utils/objects';

describe('LiquidityLayerRouter', async () => {
  const localChain = 'test1';
  const remoteChain = 'test2';
  const localDomain = ChainNameToDomainId[localChain];
  const remoteDomain = ChainNameToDomainId[remoteChain];

  let signer: SignerWithAddress;
  let local: LiquidityLayerRouter;
  let multiProvider: MultiProvider<TestChainNames>;
  let coreApp: TestCoreApp;

  let liquidityLayerApp: LiquidityLayerApp<TestChainNames>;
  let config: ChainMap<TestChainNames, LiquidityLayerConfig>;
  let mockToken: MockToken;
  let circleTokenMessenger: MockCircleTokenMessenger;
  let portalBridge: MockPortalBridge;
  let messageTransmitter: MockCircleMessageTransmitter;

  before(async () => {
    [signer] = await ethers.getSigners();

    multiProvider = getTestMultiProvider(signer);

    const coreDeployer = new TestCoreDeployer(multiProvider);
    const coreContractsMaps = await coreDeployer.deploy();
    coreApp = new TestCoreApp(coreContractsMaps, multiProvider);

    const mockTokenF = new MockToken__factory(signer);
    mockToken = await mockTokenF.deploy();
    const portalBridgeF = new MockPortalBridge__factory(signer);
    const circleTokenMessengerF = new MockCircleTokenMessenger__factory(signer);
    circleTokenMessenger = await circleTokenMessengerF.deploy(
      mockToken.address,
    );
    portalBridge = await portalBridgeF.deploy(mockToken.address);
    const messageTransmitterF = new MockCircleMessageTransmitter__factory(
      signer,
    );
    messageTransmitter = await messageTransmitterF.deploy(mockToken.address);

    config = coreApp.extendWithConnectionClientConfig(
      objMap(
        getChainToOwnerMap(testChainConnectionConfigs, signer.address),
        (_chain, conf) => ({
          ...conf,
          circle: {
            type: BridgeAdapterType.Circle,
            tokenMessengerAddress: circleTokenMessenger.address,
            messageTransmitterAddress: messageTransmitter.address,
            usdcAddress: mockToken.address,
            circleDomainMapping: [
              {
                hyperlaneDomain: localDomain,
                circleDomain: localDomain,
              },
              {
                hyperlaneDomain: remoteDomain,
                circleDomain: remoteDomain,
              },
            ],
          } as CircleBridgeAdapterConfig,
          portal: {
            type: BridgeAdapterType.Portal,
            portalBridgeAddress: portalBridge.address,
            wormholeDomainMapping: [
              {
                hyperlaneDomain: localDomain,
                wormholeDomain: localDomain,
              },
              {
                hyperlaneDomain: remoteDomain,
                wormholeDomain: remoteDomain,
              },
            ],
          } as PortalAdapterConfig,
        }),
      ),
    );
  });

  beforeEach(async () => {
    const LiquidityLayer = new LiquidityLayerDeployer(
      multiProvider,
      config,
      coreApp,
    );
    const contracts = await LiquidityLayer.deploy();

    liquidityLayerApp = new LiquidityLayerApp(contracts, multiProvider, config);

    local = liquidityLayerApp.getContracts(localChain).router;
  });

  it('can transfer tokens via Circle', async () => {
    const recipientF = new TestLiquidityLayerMessageRecipient__factory(signer);
    const recipient = await recipientF.deploy();

    const amount = 1000;
    await mockToken.mint(signer.address, amount);
    await mockToken.approve(local.address, amount);
    await local.dispatchWithTokens(
      remoteDomain,
      utils.addressToBytes32(recipient.address),
      mockToken.address,
      amount,
      BridgeAdapterType.Circle,
      '0x01',
    );

    const transferNonce = await circleTokenMessenger.nextNonce();
    const nonceId = await messageTransmitter.hashSourceAndNonce(
      localDomain,
      transferNonce,
    );

    await messageTransmitter.process(
      nonceId,
      liquidityLayerApp.getContracts(remoteChain).circleBridgeAdapter!.address,
      amount,
    );
    await coreApp.processMessages();

    expect((await mockToken.balanceOf(recipient.address)).toNumber()).to.eql(
      amount,
    );
  });

  it('can transfer tokens via Portal', async () => {
    const recipientF = new TestLiquidityLayerMessageRecipient__factory(signer);
    const recipient = await recipientF.deploy();

    const amount = 1000;
    await mockToken.mint(signer.address, amount);
    await mockToken.approve(local.address, amount);
    await local.dispatchWithTokens(
      remoteDomain,
      utils.addressToBytes32(recipient.address),
      mockToken.address,
      amount,
      BridgeAdapterType.Portal,
      '0x01',
    );

    const originAdapter =
      liquidityLayerApp.getContracts(localChain).portalAdapter!;
    const destinationAdapter =
      liquidityLayerApp.getContracts(remoteChain).portalAdapter!;
    await destinationAdapter.completeTransfer(
      await portalBridge.mockPortalVaa(
        localDomain,
        await originAdapter.nonce(),
        amount,
      ),
    );
    await coreApp.processMessages();

    expect((await mockToken.balanceOf(recipient.address)).toNumber()).to.eql(
      amount,
    );
  });
});
