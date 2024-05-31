// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract SportNft is ERC721URIStorage {
    uint256 private _tokenIds;
    string private _baseTokenURI;

    constructor() ERC721("SportNFT", "SNFT") {}

    function mintNFT(address recipient, string memory tokenURI) external returns (uint256) {
        _tokenIds++;
        uint256 newItemId = _tokenIds;

        _mint(recipient, newItemId);
        _setTokenURI(newItemId, tokenURI);
        return newItemId;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) external {
        _baseTokenURI = baseURI;
    }
}
