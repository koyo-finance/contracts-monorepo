// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPerpetualsPriceFeed {
    function description() external view returns (string memory);

    function aggregator() external view returns (address);

    function latestAnswer() external view returns (int256);

    function latestRound() external view returns (uint80);

    function getRoundData(uint80 roundId)
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );
}
