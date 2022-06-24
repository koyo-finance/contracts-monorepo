// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { Authentication } from "@koyofinance/exchange-vault-solidity-utils/contracts/helpers/Authentication.sol";
import { BasePoolAuthorization } from "@koyofinance/exchange-vault-pool-utils/contracts/BasePoolAuthorization.sol";
import {
    TemporarilyPausable
} from "@koyofinance/exchange-vault-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

import { IERC20 } from "@koyofinance/exchange-vault-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import { IBasePool } from "@koyofinance/exchange-vault-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@koyofinance/exchange-vault-interfaces/contracts/vault/IVault.sol";
import {
    IProtocolFeesCollector
} from "@koyofinance/exchange-vault-interfaces/contracts/vault/IProtocolFeesCollector.sol";
import { IAssetManager } from "@koyofinance/exchange-vault-interfaces/contracts/asset-manager-utils/IAssetManager.sol";

import { WordCodec } from "@koyofinance/exchange-vault-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@koyofinance/exchange-vault-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@koyofinance/exchange-vault-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    _require,
    Errors
} from "@koyofinance/exchange-vault-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

abstract contract BaseTokenlessPool is IBasePool, BasePoolAuthorization, TemporarilyPausable {
    using WordCodec for bytes32;
    using FixedPoint for uint256;

    uint256 private constant _MIN_TOKENS = 2;

    // 1e18 corresponds to 1.0, or a 100% fee
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 1e17; // 10% - this fits in 64 bits

    bytes32 private _miscData;
    uint256 private constant _SWAP_FEE_PERCENTAGE_OFFSET = 192;

    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    IProtocolFeesCollector private immutable _protocolFeesCollector;

    event SwapFeePercentageChanged(uint256 swapFeePercentage);

    constructor(
        IVault vault,
        IVault.PoolSpecialization specialization,
        IERC20[] memory tokens,
        address[] memory assetManagers,
        uint256 swapFeePercentage,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration,
        address owner
    )
        Authentication(bytes32(uint256(msg.sender)))
        BasePoolAuthorization(owner)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {
        _require(tokens.length >= _MIN_TOKENS, Errors.MIN_TOKENS);
        _require(tokens.length <= _getMaxTokens(), Errors.MAX_TOKENS);

        // The Vault only requires the token list to be ordered for the Two Token Pools specialization. However,
        // to make the developer experience consistent, we are requiring this condition for all the native pools.
        // Also, since these Pools will register tokens only once, we can ensure the Pool tokens will follow the same
        // order. We rely on this property to make Pools simpler to write, as it lets us assume that the
        // order of token-specific parameters (such as token weights) will not change.
        InputHelpers.ensureArrayIsSorted(tokens);

        _setSwapFeePercentage(swapFeePercentage);

        _vault = vault;
        bytes32 poolId = vault.registerPool(specialization);

        vault.registerTokens(poolId, tokens, assetManagers);

        // Set immutable state variables - these cannot be read from during construction
        _poolId = poolId;
        _protocolFeesCollector = vault.getProtocolFeesCollector();
    }


    function getVault() public view returns (IVault) {
        return _vault;
    }

    /**
     * @notice Return the pool id.
     */
    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function _getTotalTokens() internal view virtual returns (uint256);

    function _getMaxTokens() internal pure virtual returns (uint256);

    /**
     * @notice Return the current value of the swap fee percentage.
     * @dev This is stored in the MSB 64 bits of the `_miscData`.
     */
    function getSwapFeePercentage() public view virtual returns (uint256) {
        return _miscData.decodeUint(_SWAP_FEE_PERCENTAGE_OFFSET, 64);
    }

    /**
     * @notice Return the ProtocolFeesCollector contract.
     * @dev This is immutable, and retrieved from the Vault on construction. (It is also immutable in the Vault.)
     */
    function getProtocolFeesCollector() public view returns (IProtocolFeesCollector) {
        return _protocolFeesCollector;
    }

    /**
     * @notice Set the swap fee percentage.
     * @dev This is a permissioned function, and disabled if the pool is paused. The swap fee must be within the
     * bounds set by MIN_SWAP_FEE_PERCENTAGE/MAX_SWAP_FEE_PERCENTAGE. Emits the SwapFeePercentageChanged event.
     */
    function setSwapFeePercentage(uint256 swapFeePercentage) external virtual authenticate whenNotPaused {
        _setSwapFeePercentage(swapFeePercentage);
    }

    function _setSwapFeePercentage(uint256 swapFeePercentage) internal virtual {
        _require(swapFeePercentage >= _getMinSwapFeePercentage(), Errors.MIN_SWAP_FEE_PERCENTAGE);
        _require(swapFeePercentage <= _getMaxSwapFeePercentage(), Errors.MAX_SWAP_FEE_PERCENTAGE);

        _miscData = _miscData.insertUint(swapFeePercentage, _SWAP_FEE_PERCENTAGE_OFFSET, 64);
        emit SwapFeePercentageChanged(swapFeePercentage);
    }

    function _getMinSwapFeePercentage() internal pure virtual returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    function _getMaxSwapFeePercentage() internal pure virtual returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /**
     * @notice Set the asset manager parameters for the given token.
     * @dev This is a permissioned function, unavailable when the pool is paused.
     * The details of the configuration data are set by each Asset Manager. (For an example, see
     * `RewardsAssetManager`.)
     */
    function setAssetManagerPoolConfig(IERC20 token, bytes memory poolConfig)
        public
        virtual
        authenticate
        whenNotPaused
    {
        _setAssetManagerPoolConfig(token, poolConfig);
    }

    function _setAssetManagerPoolConfig(IERC20 token, bytes memory poolConfig) private {
        bytes32 poolId = getPoolId();
        (, , , address assetManager) = getVault().getPoolTokenInfo(poolId, token);

        IAssetManager(assetManager).setConfig(poolId, poolConfig);
    }

    /**
     * @notice Pause the pool: an emergency action which disables all pool functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during pool factory
     * deployment (see `TemporarilyPausable`).
     */
    function pause() external authenticate {
        _setPaused(true);
    }

    /**
     * @notice Reverse a `pause` operation, and restore a pool to normal functionality.
     * @dev This is a permissioned function that will only work on a paused pool within the Buffer Period set during
     * pool factory deployment (see `TemporarilyPausable`). Note that any paused pools will automatically unpause
     * after the Buffer Period expires.
     */
    function unpause() external authenticate {
        _setPaused(false);
    }

    function _isOwnerOnlyAction(bytes32 actionId) internal view virtual override returns (bool) {
        return
            (actionId == getActionId(this.setSwapFeePercentage.selector)) ||
            (actionId == getActionId(this.setAssetManagerPoolConfig.selector));
    }

    function _getMiscData() internal view returns (bytes32) {
        return _miscData;
    }

    /**
     * @dev Inserts data into the least-significant 192 bits of the misc data storage slot.
     * Note that the remaining 64 bits are used for the swap fee percentage and cannot be overloaded.
     */
    function _setMiscData(bytes32 newData) internal {
        _miscData = _miscData.insertBits192(newData, 0);
    }

    modifier onlyVault(bytes32 poolId) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }
}
