import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { Contract, Overrides, utils } from 'ethers';
import logger from './logger';
import { getSigner } from './signers';
import { Artifact, Libraries, Param } from './types';

export async function deploy(
  artifact: Artifact,
  args: Array<Param> = [],
  from?: SignerWithAddress,
  libs?: Libraries,
  wait?: number
): Promise<Contract> {
  if (!args) args = [];
  if (!from) from = await getSigner();
  if (libs) artifact = linkBytecode(artifact, libs);

  let overrides: Overrides = {};

  const { ethers } = await import('hardhat');
  const factory = await ethers.getContractFactory(artifact.abi, artifact.evm.bytecode.object as utils.BytesLike);

  // If 1 extra parameter was passed in, it contains overrides
  if (args.length === factory.interface.deploy.inputs.length + 1) {
    overrides = args.pop();
  }

  const deploymentData = factory.interface.encodeDeploy(args);
  const deploymentEstimatedGas = await ethers.provider.estimateGas({ data: deploymentData, from: from.address });
  logger.info(`Gas to deploy contract: ${deploymentEstimatedGas}`);

  const deployment = await factory.connect(from).deploy(...args, overrides);
  await deployment.deployTransaction.wait(wait || 1);
  return deployment.deployed();
}

export async function instanceAt(artifact: Artifact, address: string): Promise<Contract> {
  const { ethers } = await import('hardhat');
  return ethers.getContractAt(artifact.abi, address);
}

export function deploymentTxData(artifact: Artifact, args: Array<Param> = [], libs?: Libraries): string {
  if (libs) artifact = linkBytecode(artifact, libs);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const encodedConstructorArguments = new utils.Interface(artifact.abi as any[]).encodeDeploy(args);

  // Solidity contracts are deployed by sending a transaction with their creation code, concatenated by the abi-encoded
  // constructor arguments.
  // We remove the first two characters of the encoded constructor arguments as ethers returns a string with the "0x"
  // prefix.
  return `0x${artifact.evm.bytecode.object}${encodedConstructorArguments.substring(2)}`;
}

function linkBytecode(artifact: Artifact, libraries: Libraries): Artifact {
  let bytecode = artifact.evm.bytecode.object;
  for (const [, fileReferences] of Object.entries(artifact.evm.bytecode.linkReferences)) {
    for (const [libName, fixups] of Object.entries(fileReferences)) {
      const address = libraries[libName];
      if (address === undefined) continue;
      for (const fixup of fixups) {
        bytecode =
          bytecode.substr(0, fixup.start * 2) + address.substr(2) + bytecode.substr((fixup.start + fixup.length) * 2);
      }
    }
  }

  artifact.evm.bytecode.object = bytecode.toLowerCase();
  return artifact;
}
