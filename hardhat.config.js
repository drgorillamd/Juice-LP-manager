require("@nomiclabs/hardhat-waffle");
require('hardhat-deploy');

const dotenv = require('dotenv');

dotenv.config();

const RPC_URL = process.env.RPC_URL;


// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

task("add-LP", "Add liquidity to a given range, based on token amounts")
  .addParam('low', 'the lower tick of the position')
  .addParam('high', 'the highest tick of the position')
  .addParam('pool', 'the pool address')
  .addParam('amount0', 'the amount of token0 to add')
  .addParam('amount1', 'the amount of token1 to add')
  .setAction(async (taskArgs, hre) => {
    try {
      const { get } = deployments;
      const owner = (await hre.ethers.getSigners())[0];

      const pool = await ethers.getContractAt('IUniswapV3Pool', taskArgs.pool);
      const LPManagerDeployment = await get('LPManager');
      const LPManager = await ethers.getContractAt('LPManager', LPManagerDeployment.address);

      const factory = await pool.factory();
      const token0 = await ethers.getContractAt('IERC20', await pool.token0());
      const token1 = await ethers.getContractAt('IERC20', await pool.token1());
      const fee = await pool.fee();
      const WETHaddress = await LPManager.WETH();

      const _data = ethers.utils.defaultAbiCoder.encode(["address", "address", "address", "uint24"], [ factory, token0.address, token1.address, fee]);

      const liquidity = await LPManager.getLiquidityForAmounts(taskArgs.amount0, taskArgs.amount1, taskArgs.low, taskArgs.high, taskArgs.pool);

      if(token0.address == WETHaddress) {
        await token1.approve(LPManager.address, taskArgs.amount1);
        await LPManager.addLP(taskArgs.pool, taskArgs.low, taskArgs.high, liquidity, _data, {value: taskArgs.amount0});
      }

      else if(token1.address == WETHaddress) {
        await token0.approve(LPManager.address, taskArgs.amount0);
        await LPManager.addLP(taskArgs.pool, taskArgs.low, taskArgs.high, liquidity, _data, {value: taskArgs.amount1});
      }

      else {
        await token0.approve(LPManager.address, taskArgs.amount0);
        await token1.approve(LPManager.address, taskArgs.amount1);
        await LPManager.addLP(taskArgs.pool, taskArgs.low, taskArgs.high, liquidity, _data);
      }

      console.log(liquidity);
    } catch (error) {
      console.log(error);
    }
  });

task("rm-LP", "Remove liquidity of a given range + collect fees")
  .addParam('low', 'the lower tick of the position')
  .addParam('high', 'the highest tick of the position')
  .addParam('pool', 'the pool address')
  .addParam('amount', 'the liquidity amount to remove')
  .setAction(async (taskArgs, hre) => {
    try {
      const { get } = deployments;
      const owner = (await hre.ethers.getSigners())[0];

      const pool = await ethers.getContractAt('IUniswapV3Pool', taskArgs.pool);
      const LPManagerDeployment = await get('LPManager');
      const LPManager = await ethers.getContractAt('LPManager', LPManagerDeployment.address);

      const token0 = await ethers.getContractAt('IERC20', await pool.token0());
      const token1 = await ethers.getContractAt('IERC20', await pool.token1());

      await LPManager.connect(owner).removeLP(taskArgs.low, taskArgs.high, taskArgs.amount, taskArgs.pool, token0.address, token1.address);
      
      console.log(liquidity);
    } catch (error) {
      console.log(error);
    }
  });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  paths: {
    sources: "./src",
  },
  solidity: "0.8.14",
  paths: {
    sources: "./src",
    cache: "./cache_hardhat",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url: RPC_URL,
      }
    },
    localhost: {
      url: 'http://localhost:8545',
      blockGasLimit: 0x1fffffffffffff,
    },
    rinkeby: {
      url: RPC_URL,
      gasPrice: 35000000000,
      accounts: [process.env.PK],
    },
    mainnet: {
      url: RPC_URL,
      gasPrice: 35000000000,
      accounts: [process.env.PK],
    },
  },
};
