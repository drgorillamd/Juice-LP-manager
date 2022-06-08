const { ethers } = require('hardhat');

/**
 * Deploys the LPManager
 *
 * Example usage:
 *
 * npx hardhat deploy --network rinkeby
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log("Deploying...");

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let chainId = await getChainId();
  let baseDeployArgs = {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  };
  let wethAddress;

  console.log({ deployer: deployer.address, chain: chainId });

  switch (chainId) {
    // mainnet
    case '1':
      wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
      break;

    // rinkeby
    case '4':
      wethAddress = '0xc778417E063141139Fce010982780140Aa0cD5Ab';
      break;

    // hardhat / localhost
    case '31337':
      wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
      
      break;
  }

  console.log({ wethAddress });

  // Deploy a JBETHERC20ProjectPayerDeployer contract.
  await deploy('LPManager', {
    ...baseDeployArgs,
    args: [wethAddress],
  });

  console.log('Done');
};