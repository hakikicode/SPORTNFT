// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "SportNFT.sol"; // Ensure this path is correct according to your project structure

error EXPIRED();
error NotOwner();
error ListingNotExist();
error BidNotExist();
error TransferFailed();
error MinPriceTooLow();
error DurationTooShort();
error NotActive();
error InsufficientBalance();

contract SportVault is Ownable, ReentrancyGuard {

    using Strings for uint256;

    address public ERCtoken;
    address public SportNftAddress;
    AggregatorV3Interface internal priceFeed;

    uint256 public listingId;
    uint256 public totalListings;
    uint256 public listPrice;
    address public contractOwner;
    uint256 public listingPrice;

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Bid[]) public bids;

    struct Listing {
        uint256 tokenId;
        address tokenAddress;
        string tokenURI;
        uint256 price;
        uint88 deadline;
        address lister;
        bool active;
    }

    struct Bid {
        address bidder;
        uint256 amount;
        uint88 timestamp;
    }

    event ListingCreated(uint256 indexed listingId, Listing listing);
    event ListingExecuted(uint256 indexed listingId, Listing listing);
    event ListingEdited(uint256 indexed listingId, Listing listing);
    event BidPlaced(address indexed bidder, uint256 indexed listingId, uint256 amount);
    event BidWithdrawn(address indexed bidder, uint256 indexed listingId, uint256 amount);
    event BidExecuted(uint256 indexed listingId, address indexed winner, uint256 amount);
    event NFTBought(uint256 indexed listingId, address indexed buyer, uint256 amount);

    constructor(address _token, address _sportNftAddress, address _priceFeed) Ownable(msg.sender) {
        ERCtoken = _token;
        SportNftAddress = _sportNftAddress;
        contractOwner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function createListing(string memory _tokenURI, uint256 _price, uint256 _deadline) external nonReentrant {
        require(_price >= 100 * 1**18, "MinPriceTooLow");
        require(_deadline >= 80, "DurationTooShort");

        SportNft sportNft = SportNft(SportNftAddress);
        uint256 tokenId = sportNft.mintNFT(address(this), _tokenURI);

        uint88 deadline = uint88(block.timestamp) + uint88(_deadline);
        listingId++;
        listings[listingId] = Listing({
            tokenId: tokenId,
            tokenAddress: SportNftAddress,
            tokenURI: _tokenURI,
            price: _price,
            deadline: deadline,
            lister: msg.sender,
            active: true
        });
        totalListings++;

        emit ListingCreated(listingId, listings[listingId]);
    }

    function executeListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.active, "NotActive");
        require(block.timestamp <= listing.deadline, "Listing expired");
        require(msg.sender == listing.lister, "NotOwner");

        listing.active = false;

        SportNft sportNft = SportNft(SportNftAddress);
        sportNft.safeTransferFrom(address(this), msg.sender, listing.tokenId);

        emit ListingExecuted(_listingId, listing);
    }

    function createBid(uint256 _listingId) external {
        require(_listingId > 0 && _listingId <= listingId, "Listing ID does not exist");
        Listing storage listing = listings[_listingId];
        require(listing.lister != address(0), "ListingNotExistent");

        Bid memory newBid = Bid({
            bidder: msg.sender,
            amount: 0,
            timestamp: uint88(block.timestamp)
        });

        bids[_listingId].push(newBid);
    }

    function placeBid(uint256 _listingId, uint256 _amount) external nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.active, "Listing is not active");
        require(block.timestamp <= listing.deadline, "Listing expired");

        bids[_listingId].push(Bid({
            bidder: msg.sender,
            amount: _amount,
            timestamp: uint88(block.timestamp)
        }));

        emit BidPlaced(msg.sender, _listingId, _amount);
    }

    function getBidHistory(uint256 _listingId) external view returns (Bid[] memory) {
        return bids[_listingId];
    }

    function executeBid(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.active, "Listing is not active");
        require(block.timestamp <= listing.deadline, "Listing expired");

        Bid[] storage bidList = bids[_listingId];
        require(bidList.length > 0, "No bids found");

        Bid storage highestBid = bidList[0];
        for (uint256 i = 1; i < bidList.length; i++) {
            if (bidList[i].amount > highestBid.amount) {
                highestBid = bidList[i];
            }
        }

        listing.active = false;

        bool success = IERC20(ERCtoken).transferFrom(highestBid.bidder, listing.lister, highestBid.amount);
        require(success, "Transfer failed");

        SportNft sportNft = SportNft(SportNft(SportNftAddress));
        sportNft.safeTransferFrom(address(this), highestBid.bidder, listing.tokenId);

        emit BidExecuted(_listingId, highestBid.bidder, highestBid.amount);
    }

    function buyNFT(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        require(listing.active, "Listing is not active");
        require(block.timestamp <= listing.deadline, "Listing expired");

        listing.active = false;

        bool success = IERC20(ERCtoken).transferFrom(msg.sender, listing.lister, listing.price);
        require(success, "Transfer failed");

        SportNft sportNft = SportNft(SportNftAddress);
        sportNft.safeTransferFrom(address(this), msg.sender, listing.tokenId);

        emit NFTBought(_listingId, msg.sender, listing.price);
    }

    function getTokenURI(uint256 _listingId) external view returns (string memory) {
        Listing storage listing = listings[_listingId];
        return listing.tokenURI;
    }

    function getLatestPrice() public view returns (int) {
        (
            /* uint80 roundID */,
            int price,
            /* uint startedAt */,
            /* uint timeStamp */,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        return price;
    }
}
