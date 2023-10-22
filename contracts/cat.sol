// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CatNFT is ERC721, Ownable {
    using SafeERC20 for IERC20;

    // Food Token
    IERC20 public foodToken;

    // Cat Food Track
    // Mapping to track cat food balance
    mapping(uint256 => uint256) public catFoodMapping;

    // A unique token ID counter
    uint256 private tokenIdCounter;

    // Base URI for metadata
    string private baseTokenURI;

    // Mapping to store cat traits
    mapping(uint256 => string) private catTraits;

    constructor(string memory _name, string memory _symbol, string memory _baseTokenURI) ERC721(_name, _symbol) {
        baseTokenURI = _baseTokenURI;
    }

    // Mint a new cat NFT
    function mintCat(address to, string memory traits) public onlyOwner {
        uint256 tokenId = tokenIdCounter;
        _mint(to, tokenId);
        catTraits[tokenId] = traits;
        tokenIdCounter++;
    }

    // Get cat traits by token ID
    function getCatTraits(uint256 tokenId) public view returns (string memory) {
        return catTraits[tokenId];
    }

    // Override function to return the base URI
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    // Set the address of the food token
    function setFoodToken(address _newFoodToken) external onlyOwner {
        foodToken = IERC20(_newFoodToken);
    }

    // Feed a cat with food tokens
    function feed(uint256 tokenId, uint256 amount) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "You don't have permission to feed this cat");
        require(address(foodToken) != address(0), "Food token address is not set");
        
        // Check if the sender has enough food tokens
        require(foodToken.balanceOf(msg.sender) >= amount, "Not enough food tokens");

        // Burn the food tokens
        foodToken.safeTransferFrom(msg.sender, address(0), amount);

        // Add the fed amount to the catFoodMapping for the cat
        catFoodMapping[tokenId] += amount;
    }
}