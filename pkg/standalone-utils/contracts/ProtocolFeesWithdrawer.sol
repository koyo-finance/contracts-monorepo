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

import "@koyofinance/contracts-interfaces/contracts/vault/IVault.sol";

import "@koyofinance/contracts-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import "@koyofinance/contracts-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

/**
 * @title Protocol Fees Withdrawer
 * @notice Safety layer around the Protocol Fees Collector which allows withdrawals of specific tokens to be blocked.
 * This is useful for the case in which tokens which shouldn't be distributed are unexpectedly paid into the Protocol
 * Fees Collector.
 */
contract ProtocolFeesWithdrawer is SingletonAuthentication {
    using EnumerableSet for EnumerableSet.AddressSet;

    event TokenAllowlisted(IERC20 token);
    event TokenDenylisted(IERC20 token);

    IProtocolFeesCollector private immutable _protocolFeesCollector;

    EnumerableSet.AddressSet private _denylistedTokens;

    constructor(IVault vault, IERC20[] memory initialDeniedTokens) SingletonAuthentication(vault) {
        _protocolFeesCollector = vault.getProtocolFeesCollector();

        uint256 tokensLength = initialDeniedTokens.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            _denylistToken(initialDeniedTokens[i]);
        }
    }

    /**
     * @notice Returns the address of the Protocol Fee Collector.
     */
    function getProtocolFeesCollector() external view returns (IProtocolFeesCollector) {
        return _protocolFeesCollector;
    }

    /**
     * @notice Returns whether the provided token may be withdrawn from the Protocol Fee Collector
     */
    function isWithdrawableToken(IERC20 token) public view returns (bool) {
        return !_denylistedTokens.contains(address(token));
    }

    /**
     * @notice Returns whether the provided array of tokens may be withdrawn from the Protocol Fee Collector
     * @dev Returns false if any token is denylisted.
     */
    function isWithdrawableTokens(IERC20[] calldata tokens) public view returns (bool) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; ++i) {
            if (!isWithdrawableToken(tokens[i])) return false;
        }
        return true;
    }

    /**
     * @notice Returns the denylisted token at the given `index`.
     */
    function getDenylistedToken(uint256 index) external view returns (IERC20) {
        return IERC20(_denylistedTokens.at(index));
    }

    /**
     * @notice Returns the number of denylisted tokens.
     */
    function getDenylistedTokensLength() external view returns (uint256) {
        return _denylistedTokens.length();
    }

    /**
     * @notice Withdraws fees from the Protocol Fee Collector.
     * @dev Reverts if attempting to withdraw a denylisted token.
     * @param tokens - an array of token addresses to withdraw.
     * @param amounts - an array of the amounts of each token to withdraw.
     * @param recipient - the address to which to send the withdrawn tokens.
     */
    function withdrawCollectedFees(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address recipient
    ) external authenticate {
        require(isWithdrawableTokens(tokens), "Attempting to withdraw denylisted token");

        // We delegate checking of inputs and reentrancy protection to the ProtocolFeesCollector.
        _protocolFeesCollector.withdrawCollectedFees(tokens, amounts, recipient);
    }

    /**
     * @notice Marks the provided token as ineligible for withdrawal from the Protocol Fee Collector
     */
    function denylistToken(IERC20 token) external authenticate {
        _denylistToken(token);
    }

    /**
     * @notice Marks the provided token as eligible for withdrawal from the Protocol Fee Collector
     */
    function allowlistToken(IERC20 token) external authenticate {
        require(_denylistedTokens.remove(address(token)), "Token is not denylisted");
        emit TokenAllowlisted(token);
    }

    // Internal functions

    function _denylistToken(IERC20 token) internal {
        require(_denylistedTokens.add(address(token)), "Token already denylisted");
        emit TokenDenylisted(token);
    }
}
