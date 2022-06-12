import { deploy } from '@koyofinance/exchange-vault-helpers/src/contract';
import { fp } from '@koyofinance/exchange-vault-helpers/src/numbers';
import { Contract } from 'ethers';
import Token from '../../tokens/Token';
import TypesConverter from '../../types/TypesConverter';
import Vault from '../../vault/Vault';
import VaultDeployer from '../../vault/VaultDeployer';
import LinearPool from './LinearPool';
import { LinearPoolDeployment, RawLinearPoolDeployment } from './types';

const NAME = 'Balancer Pool Token';
const SYMBOL = 'BPT';

export default {
  async deploy(params: RawLinearPoolDeployment, mockedVault: boolean): Promise<LinearPool> {
    const vaultParams = TypesConverter.toRawVaultDeployment(params);
    vaultParams.mocked = mockedVault;
    const vault = params.vault ?? (await VaultDeployer.deploy(vaultParams));

    const deployment = TypesConverter.toLinearPoolDeployment(params);

    const pool = await this._deployStandalone(deployment, vault);

    const { owner, mainToken, wrappedToken, upperTarget, swapFeePercentage } = deployment;

    const poolId = await pool.getPoolId();
    const name = await pool.name();
    const symbol = await pool.symbol();
    const decimals = await pool.decimals();
    const bptToken = new Token(name, symbol, decimals, pool);
    const lowerTarget = fp(0);

    return new LinearPool(
      pool,
      poolId,
      vault,
      mainToken,
      wrappedToken,
      bptToken,
      lowerTarget,
      upperTarget,
      swapFeePercentage,
      owner
    );
  },

  async _deployStandalone(params: LinearPoolDeployment, vault: Vault): Promise<Contract> {
    const { mainToken, wrappedToken, upperTarget, swapFeePercentage, pauseWindowDuration, bufferPeriodDuration, from } =
      params;

    const owner = TypesConverter.toAddress(params.owner);

    return deploy('v2-pool-linear/MockLinearPool', {
      args: [
        vault.address,
        NAME,
        SYMBOL,
        mainToken.address,
        wrappedToken.address,
        upperTarget,
        swapFeePercentage,
        pauseWindowDuration,
        bufferPeriodDuration,
        owner,
      ],
      from,
    });
  },
};
