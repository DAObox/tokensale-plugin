import {DeployFunction} from 'hardhat-deploy/types';
import {
  activeContractsList,
  DAOFactory,
  DAOFactory__factory,
  PluginRepo__factory,
  Addresslist__factory,
  PluginRepo,
} from '@aragon/osx-ethers';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

import {defaultAbiCoder} from '@ethersproject/abi';
import {hexToBytes} from '../../utils/strings';

const ADDRESS_ZERO = `0x${'0'.repeat(40)}`;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // 01. get the dao factory
  const daoFactory = await getDaoFactory(hre);
  const [deployer] = await hre.ethers.getSigners();

  // 02. create the dao settings
  const daoSettings: DAOFactory.DAOSettingsStruct = {
    trustedForwarder: ADDRESS_ZERO,
    daoURI: 'https://daobox.app',
    subdomain: 'testingggg',
    metadata: '0x00',
  };

  // 03. create the plugin settings
  const pluginSettings: DAOFactory.PluginSettingsStruct =
    await getAdminPluginInstallData(hre);

  const address = await getAragonAddress('admin-repo', hre);

  const adminRepo = PluginRepo__factory.connect(address, deployer);
  console.log(await adminRepo.latestRelease());

  // const adminPlugin =  function getRepo("admin-repo", hre);

  // 04. create the dao
  // const tx = await daoFactory.createDao(daoSettings, [pluginSettings]);

  // console.log(tx);
};

export default func;
func.tags = ['Admin_DAO'];

export async function getDaoFactory(hre: HardhatRuntimeEnvironment) {
  const {network} = hre;
  const [deployer] = await hre.ethers.getSigners();

  const daoFactoryAddress =
    network.name === 'localhost' ||
    network.name === 'hardhat' ||
    network.name === 'coverage'
      ? activeContractsList.mainnet.DAOFactory
      : activeContractsList[network.name as keyof typeof activeContractsList]
          .DAOFactory;

  return DAOFactory__factory.connect(daoFactoryAddress, deployer);
}

export async function getAdminPluginInstallData(
  hre: HardhatRuntimeEnvironment
): Promise<DAOFactory.PluginSettingsStruct> {
  const {network} = hre;
  const [deployer] = await hre.ethers.getSigners();

  const adminRepoAddress =
    network.name === 'localhost' ||
    network.name === 'hardhat' ||
    network.name === 'coverage'
      ? activeContractsList.mainnet.DAOFactory
      : activeContractsList[network.name as keyof typeof activeContractsList]
          .DAOFactory;

  const deployemnt = defaultAbiCoder.encode(['address'], [deployer.address]);

  return {
    pluginSetupRef: getPluginSetupRefStruct(adminRepoAddress),
    data: hexToBytes(deployemnt),
  };
}

// TODO: this should call the repo and get the latest version
function getPluginSetupRefStruct(repoAddress: string) {
  const versionTag: PluginRepo.TagStruct = {
    release: 1,
    build: 1,
  };

  return {
    versionTag,
    pluginSetupRepo: repoAddress,
  };
}

async function getAragonAddress(
  name: keyof typeof activeContractsList.mainnet,
  hre: HardhatRuntimeEnvironment
) {
  const {network} = hre;
  const [deployer] = await hre.ethers.getSigners();

  return network.name === 'localhost' ||
    network.name === 'hardhat' ||
    network.name === 'coverage'
    ? activeContractsList.mainnet.DAOFactory
    : activeContractsList[network.name as keyof typeof activeContractsList][
        name
      ];
}

async function getRepo(
  name: keyof typeof activeContractsList.mainnet,
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();

  const address = await getAragonAddress(name, hre);
  return PluginRepo__factory.connect(address, deployer);
}
