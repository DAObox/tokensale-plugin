// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {TokensalePlugin} from "./TokensalePlugin.sol";

contract TokensaleSetup is PluginSetup {
    /// @notice The address of the `TokensalePlugin` base contract.
    TokensalePlugin private immutable tokenSale;

    /// @notice The error thrown when the helpers array length is not x.
    error WrongHelpersArrayLength(uint length);

    /// @notice The contract constructor, that deployes the bases.
    constructor() {
        tokenSale = new TokensalePlugin();
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // 1. Decode the data.
        (address token, uint256 rate, uint256 weiLimit, uint256 startBlock, uint256 endBlock) = abi
            .decode(_data, (address, uint256, uint256, uint256, uint256));

        // 2. Prepare and deploy plugin proxy.
        plugin = createERC1967Proxy(
            address(tokenSale),
            abi.encodeWithSelector(
                TokensalePlugin.initialize.selector,
                _dao,
                token,
                rate,
                weiLimit,
                startBlock,
                endBlock
            )
        );

        // 3. Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Grant the DAO contract `CREATE_PROPOSAL_PERMISSION_ID` of the plugin.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            token,
            plugin,
            PermissionLib.NO_CONDITION,
            GovernanceERC20(token).MINT_PERMISSION_ID()
        );

        // Grant the DAO contract `CONFIGURE_PERMISSION_ID` of the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Grant,
            plugin,
            address(_dao),
            PermissionLib.NO_CONDITION,
            tokenSale.CONFIGURE_PERMISSION_ID()
        );

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions.

        permissions = new PermissionLib.MultiTargetPermission[](2);
        address token = _payload.currentHelpers[0];

        // Revoke the DAO contract `CREATE_PROPOSAL_PERMISSION_ID` of the plugin.
        permissions[0] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            token,
            _payload.plugin,
            PermissionLib.NO_CONDITION,
            GovernanceERC20(token).MINT_PERMISSION_ID()
        );

        // Revoke the DAO contract `CONFIGURE_PERMISSION_ID` of the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            address(_dao),
            PermissionLib.NO_CONDITION,
            tokenSale.CONFIGURE_PERMISSION_ID()
        );
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(tokenSale);
    }
}
