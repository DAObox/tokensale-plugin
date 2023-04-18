import {
  DAOFactory,
  DAORegistry__factory,
  activeContractsList,
  DAOFactory__factory,
  PluginRepo,
  PluginRepo__factory,
} from '@aragon/osx-ethers';
import {defaultAbiCoder} from '@ethersproject/abi';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {ADDRESS_ZERO} from '../test/simple-storage/simple-storage-common';
import {findEventTopicLog} from './helpers';
import {hexToBytes} from './strings';
import {toUtf8Bytes} from '@ethersproject/strings';

class DAOHelpers {
  private hre: HardhatRuntimeEnvironment;

  constructor(hre: HardhatRuntimeEnvironment) {
    this.hre = hre;
  }

  public async createDao(
    daoSettings: DAOFactory.DAOSettingsStruct,
    installItems: Array<DAOFactory.PluginSettingsStruct>
  ) {
    const [deployer] = await this.hre.ethers.getSigners();
    const {metadata, ...rest} = daoSettings;

    const factory = await this.daoFactory();
    const tx = await factory.createDao(
      {
        metadata: toUtf8Bytes(`ipfs://${daoSettings.metadata}`),
        ...rest,
      },
      installItems
    );
    const txHash = tx.hash;
    console.log('txHash', txHash);
    await tx.wait();

    const iface = DAORegistry__factory.connect(
      ADDRESS_ZERO,
      deployer
    ).interface;

    const {dao, creator, subdomain} = (
      await findEventTopicLog(tx, iface, 'DAORegistered')
    ).args;

    console.log({dao, creator, subdomain, txHash});
    return dao;
  }

  public async daoFactory() {
    const {hre} = this;
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

  public async getAdminPluginInstallData(
    plugin: PluginRepo
  ): Promise<DAOFactory.PluginSettingsStruct> {
    const {hre, getPluginSetupRef} = this;
    const [deployer] = await hre.ethers.getSigners();
    const deployemnt = defaultAbiCoder.encode(['address'], [deployer.address]);

    return {
      pluginSetupRef: await getPluginSetupRef(plugin),
      data: hexToBytes(deployemnt),
    };
  }

  public async getRepo(address: string) {
    const {hre} = this;
    const [deployer] = await hre.ethers.getSigners();

    return PluginRepo__factory.connect(address, deployer) as PluginRepo;
  }

  public async getPluginSetupRef(repo: PluginRepo) {
    const currentRelease = await repo.latestRelease();
    const latestVersion = await repo['getLatestVersion(uint8)'](currentRelease);

    return {
      pluginSetupRepo: repo.address,
      versionTag: latestVersion.tag,
    };
  }
}

export function createDaoHelpers(hre: HardhatRuntimeEnvironment) {
  const daoHelpers = new DAOHelpers(hre);

  return {
    getRepo: daoHelpers.getRepo.bind(daoHelpers),
    getAdminPluginInstallData:
      daoHelpers.getAdminPluginInstallData.bind(daoHelpers),
    createDao: daoHelpers.createDao.bind(daoHelpers),
    daoFactory: daoHelpers.daoFactory.bind(daoHelpers),
    getPluginSetupRef: daoHelpers.getPluginSetupRef.bind(daoHelpers),
  };
}
