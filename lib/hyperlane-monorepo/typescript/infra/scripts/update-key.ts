import {
  getContextAgentConfig,
  getEnvironment,
  getKeyRoleAndChainArgs,
} from './utils';

async function rotateKey() {
  const args = getKeyRoleAndChainArgs();
  const argv = await args.argv;

  const environment = await getEnvironment();
  const agentConfig = await getContextAgentConfig();

  switch (environment) {
    // TODO: Reimplement this when the environments get readded
    case 'test': {
      console.log("I don't do anything");
      console.log(argv, agentConfig);
    }
    // case DeployEnvironment.testnet:
    // case DeployEnvironment.mainnet:
    //   const key = new AgentAwsKey(agentConfig, argv.r, argv.c);
    //   await key.fetch();
    //   console.log(`Current key: ${key.address}`);
    //   await key.update();
    //   console.log(`Create new key with address: ${key.address}`);
    //   console.log('Run rotate-key script to rotate the key via the alias.');
    //   break;
    // default: {
    //   throw new Error('invalid environment');
    //   break;
    // }
  }
}

rotateKey().then(console.log).catch(console.error);
