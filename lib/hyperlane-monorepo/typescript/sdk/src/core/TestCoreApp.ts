import { ethers } from 'ethers';

import { TestMailbox } from '@hyperlane-xyz/core';
import { utils } from '@hyperlane-xyz/utils';

import { chainMetadata } from '../consts/chainMetadata';
import { DomainIdToChainName } from '../domains';
import { ProxiedContract } from '../proxy';
import { ChainName, TestChainNames } from '../types';

import { HyperlaneCore } from './HyperlaneCore';
import { CoreContracts } from './contracts';

type MockProxyAddresses = {
  kind: 'MOCK';
  proxy: string;
  implementation: string;
};

export type TestCoreContracts = CoreContracts & {
  mailbox: ProxiedContract<TestMailbox, MockProxyAddresses>;
};

export class TestCoreApp<
  TestChain extends TestChainNames = TestChainNames,
> extends HyperlaneCore<TestChain> {
  getContracts<Local extends TestChain>(chain: Local): TestCoreContracts {
    return super.getContracts(chain) as TestCoreContracts;
  }

  async processMessages(): Promise<
    Map<TestChain, Map<TestChain, ethers.providers.TransactionResponse[]>>
  > {
    const responses = new Map();
    for (const origin of this.chains()) {
      const outbound = await this.processOutboundMessages(origin);
      const originResponses = new Map();
      this.remoteChains(origin).forEach((destination) =>
        originResponses.set(destination, outbound.get(destination)),
      );
      responses.set(origin, originResponses);
    }
    return responses;
  }

  async processOutboundMessages<Local extends TestChain>(
    origin: Local,
  ): Promise<Map<ChainName, ethers.providers.TransactionResponse[]>> {
    const responses = new Map<ChainName, any>();
    const contracts = this.getContracts(origin);
    const outbox: TestMailbox = contracts.mailbox.contract;

    const dispatchFilter = outbox.filters.Dispatch();
    const dispatches = await outbox.queryFilter(dispatchFilter);
    for (const dispatch of dispatches) {
      const destination = dispatch.args.destination;
      if (destination === chainMetadata[origin].id) {
        throw new Error('Dispatched message to local domain');
      }
      const destinationChain = DomainIdToChainName[destination] as TestChain;
      const inbox = this.getContracts(destinationChain).mailbox.contract;
      const id = utils.messageId(dispatch.args.message);
      const delivered = await inbox.delivered(id);
      if (!delivered) {
        const response = await inbox.process('0x', dispatch.args.message);
        const destinationResponses = responses.get(destinationChain) || [];
        destinationResponses.push(response);
        responses.set(destinationChain, destinationResponses);
      }
    }
    return responses;
  }
}
