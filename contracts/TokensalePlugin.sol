// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IDAO, PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IERC20MintableUpgradeable} from "@aragon/osx/token/ERC20/IERC20MintableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title TokensalePlugin
/// @author Aaron Abu Usama (@pythonpete32)
/// @notice A plugin that manages token sales for an organization using the Aragon OSx framework.
contract TokensalePlugin is PluginUUPSUpgradeable, ReentrancyGuardUpgradeable {
    // ====================================================================================== //
    //                                     Constants                                          //
    // ====================================================================================== //

    /// @notice The ID of the permission required to call the `rule` function.
    bytes32 public constant CONFIGURE_PERMISSION_ID = keccak256("CONFIGURE_PERMISSION");

    /// @notice The IERC20MintableUpgradeable token instance that will be sold during the token sale.
    IERC20MintableUpgradeable private token_;

    // ====================================================================================== //
    //                                     Variables                                          //
    // ====================================================================================== //

    /// @notice The conversion rate between wei and the smallest indivisible token unit,
    ///         determining how many token units a buyer receives per wei during the token sale.
    /// @dev If using a rate of 1 with a token with 3 decimals called TOK, 1 wei will give
    //       the buyer 1 unit, or 0.001 TOK.
    uint256 private rate_;

    /// @notice The total amount of wei raised during the token sale.
    /// @dev This value is updated every time a purchase is made.
    uint256 private weiRaised_;

    /// @notice The maximum amount of wei that can be raised during the token sale.
    uint256 private weiLimit_;

    /// @notice The starting block number for the token sale.
    uint256 private startBlock_;

    /// @notice The ending block number for the token sale.
    uint256 private endBlock_;

    /// @notice A boolean value representing whether the token sale is paused or not.
    bool private isPaused_;

    // ====================================================================================== //
    //                                       Events                                           //
    // ====================================================================================== //

    /// @notice Event emitted when tokens are purchased during the token sale.
    /// @param purchaser The address of the account that initiated the purchase.
    /// @param beneficiary The address of the account that will receive the purchased tokens.
    /// @param value The amount of wei spent on the purchase.
    /// @param amount The amount of tokens purchased.
    event TokensPurchased(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 amount
    );

    /// @notice Event emitted when the sale configuration is updated.
    /// @param rate The new conversion rate between wei and the smallest indivisible token unit.
    /// @param weiLimit The new maximum amount of wei that can be raised during the token sale.
    /// @param startBlock The new starting block number for the token sale.
    /// @param endBlock The new ending block number for the token sale.
    event SaleConfigured(uint256 rate, uint256 weiLimit, uint256 startBlock, uint256 endBlock);

    /// @notice Event emitted when the token sale is paused or unpaused.
    /// @param isPaused The new pause status of the token sale (true for paused, false for unpaused).
    event IsSalePaused(bool isPaused);

    // ====================================================================================== //
    //                                       Errors                                           //
    // ====================================================================================== //

    /// @notice Custom error emitted when an invalid rate is provided.
    error InvalidRate(uint256 rate);

    /// @notice Custom error emitted when a token purchase fails.
    error BuyTokensFailed(address buyer, address beneficiary, uint256 value, uint256 tokens);

    /// @notice Custom error emitted when an invalid token is provided.
    error InvalidToken(address token);

    /// @notice Custom error emitted when an invalid configuration value is provided.
    error InvalidConfig(bytes32 param, bytes value);

    /// @notice Custom error emitted when trying to interact with the token sale while it is paused.
    error SalePaused();

    /// @notice Custom error emitted when an invalid time range is provided.
    error InvalidTime(uint256 startBlock, uint256 endBlock);

    /// @notice Custom error emitted when attempting to interact with the token sale before it is open.
    error SaleNotOpen(uint256 startBlock, uint256 endBlock, uint256 currentBlock);

    /// @notice Custom error emitted when the token sale reaches its wei limit.
    error CapReached(uint256 weiRaised, uint256 weiLimit);

    // ====================================================================================== //
    //                                       Setup                                            //
    // ====================================================================================== //

    /// @notice Initializes the TokensalePlugin contract with the provided parameters.
    /// @dev This function should only be called once, during the contract's deployment.
    /// @param _dao The address of the DAO that the plugin will be associated with.
    /// @param _token The address of the ERC20 token to be sold during the token sale.
    /// @param _rate The conversion rate between wei and the smallest indivisible token unit.
    /// @param _weiLimit The maximum amount of wei that can be raised during the token sale.
    /// @param _startBlock The starting block number for the token sale.
    /// @param _endBlock The ending block number for the token sale.
    function initialize(
        IDAO _dao,
        IERC20MintableUpgradeable _token,
        uint256 _rate,
        uint256 _weiLimit,
        uint256 _startBlock,
        uint256 _endBlock
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
        if (_rate > 0) revert InvalidRate({rate: _rate});
        if (address(token_) != address(0)) revert InvalidToken({token: address(token_)});
        if (_startBlock > _endBlock)
            revert InvalidTime({startBlock: _startBlock, endBlock: _endBlock});
        rate_ = _rate;
        weiLimit_ = _weiLimit;
        startBlock_ = _startBlock;
        endBlock_ = _endBlock;
        token_ = _token;
        isPaused_ = false;
    }

    // ====================================================================================== //
    //                                     Write Funcs                                        //
    // ====================================================================================== //

    /// @notice Allows users to purchase tokens with ether during the token sale, minting tokens for the specified beneficiary and transferring ether to the DAO.
    /// @param _beneficiary The address of the account that will receive the purchased tokens.
    function buyTokens(address _beneficiary) public payable nonReentrant {
        uint256 weiAmount = msg.value;
        weiRaised_ = weiRaised_ + weiAmount;

        // 1. validate time
        if (block.number < startBlock_)
            revert SaleNotOpen({
                startBlock: startBlock_,
                endBlock: endBlock_,
                currentBlock: block.number
            });

        // 2. validate paused
        if (isPaused_) revert SalePaused();

        // 3. validate cap
        if (msg.value + weiRaised_ > weiLimit_)
            revert CapReached({weiRaised: weiRaised_, weiLimit: weiLimit_});

        // 4. calculate token amount to be created
        uint256 tokens = _getTokenAmount(weiAmount);

        // 5. mint tokens
        token_.mint(_beneficiary, tokens);

        // 6. send eth to dao
        (bool success, ) = payable(address(dao())).call{value: weiAmount}("");
        if (!success)
            revert BuyTokensFailed({
                buyer: _msgSender(),
                beneficiary: _beneficiary,
                value: weiAmount,
                tokens: tokens
            });

        // 7. emit event
        emit TokensPurchased(_msgSender(), _beneficiary, weiAmount, tokens);
    }

    /// @notice Updates the conversion rate between wei and the smallest indivisible token unit.
    /// @param _rate The new conversion rate.
    function setRate(uint256 _rate) external auth(CONFIGURE_PERMISSION_ID) {
        rate_ = _rate;
        emit SaleConfigured(rate_, weiLimit_, startBlock_, endBlock_);
    }

    /// @notice Updates the pause status of the token sale.
    /// @param _isPaused The new pause status (true for paused, false for unpaused).
    function setIsPaused(bool _isPaused) external auth(CONFIGURE_PERMISSION_ID) {
        isPaused_ = _isPaused;
        emit SaleConfigured(rate_, weiLimit_, startBlock_, endBlock_);
    }

    /// @notice Updates the starting block number for the token sale.
    /// @param _startBlock The new starting block number.
    function setStartBlock(uint256 _startBlock) external auth(CONFIGURE_PERMISSION_ID) {
        startBlock_ = _startBlock;
        emit SaleConfigured(rate_, weiLimit_, startBlock_, endBlock_);
    }

    /// @notice Updates the ending block number for the token sale.
    /// @param _endBlock The new ending block number.
    function setEndBlock(uint256 _endBlock) external auth(CONFIGURE_PERMISSION_ID) {
        endBlock_ = _endBlock;
        emit SaleConfigured(rate_, weiLimit_, startBlock_, endBlock_);
    }

    // ====================================================================================== //
    //                                     Read Funcs                                         //
    // ====================================================================================== //

    /// @notice Calculates the amount of tokens to be minted based on the provided wei amount.
    /// @param weiAmount The amount of wei used to purchase tokens.
    /// @return The amount of tokens to be minted.
    function _getTokenAmount(uint256 weiAmount) public view returns (uint256) {
        return weiAmount * rate_;
    }

    /// @notice Returns the IERC20MintableUpgradeable token instance being sold during the token sale.
    function token() public view returns (IERC20MintableUpgradeable) {
        return token_;
    }

    /// @notice Returns the conversion rate between wei and the smallest indivisible token unit.
    function rate() public view returns (uint256) {
        return rate_;
    }

    /// @notice Returns the pause status of the token sale (true if paused, false if not).
    function isPaused() public view returns (bool) {
        return isPaused_;
    }

    /// @notice Returns the total amount of wei raised during the token sale.
    function weiRaised() public view returns (uint256) {
        return weiRaised_;
    }

    /// @notice Returns the maximum amount of wei that can be raised during the token sale.
    function weiLimit() public view returns (uint256) {
        return weiLimit_;
    }

    /// @notice Returns the starting block number for the token sale.
    function startBlock() public view returns (uint256) {
        return startBlock_;
    }

    /// @notice Returns the ending block number for the token sale.
    function endBlock() public view returns (uint256) {
        return endBlock_;
    }

    /// @notice Checks if the token sale is open, considering the pause status and the current block number.
    /// @return A boolean value representing whether the token sale is open (true) or
    function isSaleOpen() public view returns (bool) {
        if (isPaused_) return false;
        return block.number >= startBlock_ && block.number <= endBlock_;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[49] private __gap;
}
