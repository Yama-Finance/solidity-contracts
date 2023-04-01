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
    // TODO: re-implement this when the environments actually get readded
    case 'test': {
      console.log("I don't do anything");
      console.log(argv, agentConfig);
    }
    // case DeployEnvironment.dev: {
    //   await rotateGCPKey(environment, argv.r, argv.c);
    //   break;
    // }
    // case DeployEnvironment.testnet:
    // case DeployEnvironment.mainnet:
    //   const key = new AgentAwsKey(agentConfig, argv.r, argv.c);
    //   await key.fetch();
    //   console.log(`Current key: ${key.address}`);
    //   await key.rotate();
    //   console.log(`Key was rotated to ${key.address}. `);
    //   break;
    // default: {
    //   throw new Error('invalid environment');
    //   break;
    // }
  }
}

rotateKey().then(console.log).catch(console.error);
