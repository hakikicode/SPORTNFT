// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

error EXPIRED();

contract SportVault is Ownable, ReentrancyGuard {

    using Strings for uint256;
    address public ERCtoken;
    address public SoccerNft;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Bid) private _bids;
    uint256 public listingId;
    uint256 public totalListings;
    uint256 public listPrice;
    address public contractOwner;
    uint256 public listingPrice;
    AggregatorV3Interface internal priceFeed;

    struct Listing {
        uint256 tokenId;
        address tokenAddress;
        uint256 price;
        uint88 deadline;
        address lister;
        bool active;
    }

    struct Bid {
        uint256 tokenId;
        uint256 price;
        uint88 deadline;
        address lister;
        bool active;
        uint256 highestBid;
        uint256 bidBalance;
        address highestBidder;
    }

    Bid[] public bids;
    mapping(uint256 => Bid) public Createdbids;
    
    event ListingCreated(uint256 indexed listingId, Listing listing);
    event ListingExecuted(uint256 indexed listingId, Listing listing);
    event ListingEdited(uint256 indexed listingId, Listing listing);
    event BidPlaced(address indexed bidder, uint256 indexed tokenId, uint256 amount);
    event BidWithdrawn(address indexed bidder, uint256 indexed tokenId, uint256 amount);
    event BidExecuted(uint256 indexed bidId, address indexed winner, uint256 indexed highestBid);

    constructor(address _token, address _soccerNft, address _priceFeed) Ownable(msg.sender) {
        ERCtoken = _token;
        SoccerNft = _soccerNft;
        contractOwner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function createListing(address _tokenAddress, uint256 _tokenId, uint256 _price, uint256 _deadline) external nonReentrant {
        require(_price >= 100 * 1**18, "MinPriceTooLow");
        require(_deadline >= 80, "DurationTooShort");

        // Transfer the NFT to the contract
        uint88 deadline = uint88(block.timestamp) + uint88(_deadline);
        listingId++;
        listings[listingId] = Listing({
            tokenId: _tokenId,
            price: _price,
            deadline: deadline,
            lister: msg.sender,
            tokenAddress: _tokenAddress,
            active: true
        });
        totalListings++;

        emit ListingCreated(listingId, listings[listingId]);
    }

    function executeListing(uint256 _listingId) external nonReentrant {
        require(_listingId > 0 && _listingId <= listingId, "Listing ID does not exist");
        Listing storage listing = listings[_listingId];
        require(listing.lister != address(0), "Listing not existent");
        require(listing.active, "Listing not active");
        require(block.timestamp <= listing.deadline, "Listing expired");

        // Update state
        listing.active = false;

        emit ListingExecuted(_listingId, listing);
    }

    function createBid(uint256 _listingId) external {
        require(_listingId > 0 && _listingId <= listingId, "Listing ID does not exist");
        Listing storage listing = listings[_listingId];
        require(listing.lister != address(0), "ListingNotExistent");

        Bid storage bid = Createdbids[_listingId];
        bid.lister = listing.lister;
        bid.tokenId = _listingId;
        bid.price = listing.price;
        bid.active = true;
        bid.deadline = uint88(block.timestamp) + 80;

        bids.push(bid);
    }

    function placeBid(uint256 tokenId, uint256 price) external {
        Bid storage bid = Createdbids[tokenId];
        require(price > bid.highestBid, "Less than highestBid");

        bid.highestBid = price;
        bid.highestBidder = msg.sender;

        emit BidPlaced(msg.sender, tokenId, price);
    }

    function getHighestBidder(uint256 bidId) external view returns (address) {
        Bid memory bid = Createdbids[bidId];
        return bid.highestBidder;
    }

    function executeBid(uint256 bidId) external nonReentrant {
        Bid storage bid = Createdbids[bidId];
        //require(bid.active, "Bid is not active");
        uint256 highestBid = bid.highestBid;
        address winner = bid.highestBidder;

        bid.active = false;

        // Transfer the highest bid amount from the winner to the contract
        bool success = IERC20(ERCtoken).transferFrom(winner, address(this), highestBid);
        require(success, "Transfer failed");

        uint256 fee = (highestBid * 10) / 100;
        uint256 balance = highestBid - fee;
        bid.bidBalance = balance;

        // Ensure the contract has approval to transfer the NFT
        IERC721 token = IERC721(SoccerNft);
        
        // Transfer the NFT to the highest bidder
        token.safeTransferFrom(bid.lister, winner, bid.tokenId);

        emit BidExecuted(bidId, winner, highestBid);
    }

    function withdrawFunds(uint256 amount, uint256 bidId) external nonReentrant {
        Bid storage bid = Createdbids[bidId];
        require(msg.sender == bid.lister, "Not your bid");
        require(bid.bidBalance >= amount, "Insufficient Balance");

        // Update balance before transfer
        bid.bidBalance -= amount;

        IERC20(ERCtoken).transfer(bid.lister, amount);
    }

        // Function to fetch item from IPFS based on CID
    function fetchIPFSItem(string memory cid) public pure returns (string memory) {
    return string(abi.encodePacked("https://ipfs.io/ipfs/", cid));
    }

    // Additional helper functions

    function updateListPrice(uint256 _listPrice) public payable {
        require(contractOwner == msg.sender, "Only owner can update listing price");
        listPrice = _listPrice;
    }

    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    function getAllNFTs() external view returns (Listing[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= listingId; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }

        Listing[] memory activeListings = new Listing[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= listingId; i++) {
            if (listings[i].active) {
                activeListings[currentIndex] = listings[i];
                currentIndex++;
            }
        }
        return activeListings;
    }

    function getMyNFTs() public view returns (Listing[] memory) {
        uint256 totalItemCount = listingId;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (listings[i].lister == msg.sender || IERC721(listings[i].tokenAddress).ownerOf(listings[i].tokenId) == msg.sender) {
                itemCount++;
            }
        }

        Listing[] memory items = new Listing[](itemCount);
        for (uint256 i = 1; i <= totalItemCount; i++) {
            if (listings[i].lister == msg.sender || IERC721(listings[i].tokenAddress).ownerOf(listings[i].tokenId) == msg.sender) {
                uint256 currentId = i;
                Listing storage currentItem = listings[currentId];
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        return items;
    }

    function getAllListings() external view returns (Listing[] memory) {
        Listing[] memory activeListings = new Listing[](totalListings);
        uint256 count = 0;
        for (uint256 i = 1; i <= listingId; i++) {
            if (listings[i].active) {
                activeListings[count] = listings[i];
                count++;
            }
        }
        assembly {mstore(activeListings, count)}
        return activeListings;
    }

    function getListingsByAddress(address owner) external view returns (Listing[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= listingId; i++) {
            if (listings[i].lister == owner) {
                count++;
            }
        }

        Listing[] memory userList = new Listing[](count);
        uint256 currentIndex = 0;
        for (uint256 i = 1; i <= listingId; i++) {
            if (listings[i].lister == owner) {
                userList[currentIndex] = listings[i];
                currentIndex++;
            }
        }
        return userList;
    }

    function getBid(uint256 bidId) external view returns (Bid memory) {
        return Createdbids[bidId];
    }

    function getAllBids() external view returns (Bid[] memory) {
        return bids;
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