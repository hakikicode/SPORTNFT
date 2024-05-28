// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SoccerERC20 is ERC20 {
    constructor() ERC20("MockToken", "MKT") {
        _mint(msg.sender, 10000 * (10 ** 18)); // Mint 10,000 tokens to deployer
    }
}