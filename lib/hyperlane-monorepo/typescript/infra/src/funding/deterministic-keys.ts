import { Wallet } from 'ethers';
import { HDNode } from 'ethers/lib/utils';

import { Contexts } from '../../config/contexts';
import { AgentGCPKey } from '../agents/gcp';
import { KEY_ROLE_ENUM } from '../agents/roles';

// Keys that are derived from the deployer key, mainly to have deterministic addresses on every chain
// The order here matters so don't mix it up
export enum DeterministicKeyRoles {
  InterchainAccount,
  TestRecipient,
  Create2Factory,
}

const DeterministicKeyRoleNonces = {
  [DeterministicKeyRoles.InterchainAccount]: 0,
  [DeterministicKeyRoles.TestRecipient]: 0,
  [DeterministicKeyRoles.Create2Factory]: 0,
};

export const getDeterministicKey = async (
  environment: string,
  deterministicKeyRole: DeterministicKeyRoles,
) => {
  const deployerKey = new AgentGCPKey(
    environment,
    Contexts.Hyperlane,
    KEY_ROLE_ENUM.Deployer,
  );
  await deployerKey.fetch();
  const seed = HDNode.fromSeed(deployerKey.privateKey);
  const derivedKey = seed.derivePath(
    `m/44'/60'/0'/${deterministicKeyRole}/${DeterministicKeyRoleNonces[deterministicKeyRole]}`,
  );
  return new Wallet(derivedKey.privateKey);
};
