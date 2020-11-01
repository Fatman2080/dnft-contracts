// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DNFTLibrary.sol";
import "./interfaces/IDNFTProduct.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DNFTMain is Pausable, Ownable {

    struct Player {
        address addr;
        address parent;
        address[] children;
        uint256 buyCount;
        uint256 withdrawTotalValue;
    }

    address public mainCreator;
    address payable public withdrawTo;
    IERC20 public dnftToken;

    mapping(string => address) private _products;
    mapping(string => Lib.ProductCount) private _productsCount;
    string[] private _productNames;
    string public rewardProductName;

    mapping(address => Player) private _players;

    mapping(address => address) public _playerParents;

    mapping(address => address[]) public _playerChildren;

    event ProductBuy(address player, string product, uint256 cost, uint256 tokenId);
    event ProductReward(address to, address from, string fromProduct, string toProduct, uint256 cost, uint256 fromTokenId, uint256 toTokenId);
    event ProductMintBegin(address player, string product, uint256 tokenId);
    event ProductMintWithdraw(address player, string product, uint256 tokenId, uint256 value);
    event ProductMintRedeem(address player, string product, uint256 tokenId, uint256 value);


    constructor(address _dnftAddr, address payable _withdrawTo) public {
        mainCreator = msg.sender;
        withdrawTo = _withdrawTo;
        dnftToken = IERC20(_dnftAddr);
    }


    function _getPlayer(address addr) private returns (Player storage){
        if (_players[addr].addr == address(0)) {
            Player memory player;
            player.addr = addr;
            _players[addr] = player;
        }
        return _players[addr];
    }

    function _getProduct(string memory name) private view returns (IDNFTProduct){
        require(_products[name] != address(0), "Product not exists.");
        return IDNFTProduct(_products[name]);
    }

    function setRewardProductName(string calldata name) external {
        require(_products[name] != address(0), "Product not exists.");
        rewardProductName = name;
    }

    function withdrawToken(address token, uint256 value) external {
        require(msg.sender == withdrawTo, "Must be withdraw account.");
        IERC20(token).transfer(withdrawTo, value);
    }

    function withdrawETH(uint256 value) external {
        require(msg.sender == withdrawTo, "Must be withdraw account.");
        withdrawTo.transfer(value);
    }

    function getPlayer(address addr) external view returns (Player memory){
        return _players[addr];
    }

    function getProductAddress(string calldata name) external view returns (address){
        require(_products[name] != address(0), "Product not exists.");
        return _products[name];
    }

    function getProductCount(string calldata name) external view returns (Lib.ProductCount memory){
        require(_products[name] != address(0), "Product not exists.");
        return _productsCount[name];
    }

    function getProductNames() external view returns (string[] memory){
        return _productNames;
    }

    function addProduct(address paddr, uint256 dnftValue) external onlyOwner {
        IDNFTProduct p = IDNFTProduct(paddr);
        string memory name = p.name();
        require(_products[name] == address(0), "Product already exists.");
        require(p.owner() == address(this), "Product owner not main.");
        _products[name] = paddr;
        _productNames.push(name);
        require(dnftToken.transfer(paddr, dnftValue), "DNFT Token transfer fail.");
    }

    function buyProduct(string calldata name, address playerParent) external payable {
        IDNFTProduct p = _getProduct(name);
        if (bytes(rewardProductName).length != 0)
            require(address(p) != _products[rewardProductName], "This product cannot be purchased.");
        address costTokenAddr = p.costTokenAddr();
        uint256 cost = p.cost();
        if (costTokenAddr == address(0))
            require(msg.value == cost, "Pay value wrong.");
        else {
            require(msg.value == 0, "Pay value must be zero.");
            require(IERC20(costTokenAddr).transferFrom(msg.sender, address(this), cost), "Token transfer fail.");
        }
        require(playerParent != msg.sender, "Pay parent wrong.");
        Player storage player = _getPlayer(msg.sender);
        if (playerParent != address(0)) {
            Player storage parentPlayer = _getPlayer(playerParent);
            player.parent = playerParent;
            parentPlayer.children.push(player.addr);
        }
        _productsCount[name].buyCount++;
        player.buyCount++;
        uint256 tokenId = p.buy(msg.sender);
        emit ProductBuy(msg.sender, name, msg.value, tokenId);
        if (player.buyCount == 1 && player.parent != address(0) && bytes(rewardProductName).length != 0) {
            uint256 toTokenId = IDNFTProduct(_products[rewardProductName]).buy(player.parent);
            emit ProductReward(player.parent, msg.sender, name, rewardProductName, msg.value, tokenId, toTokenId);
        }
    }

    function mintBegin(string calldata name, uint256 tokenId) external {
        IDNFTProduct p = _getProduct(name);
        p.mintBegin(msg.sender, tokenId);
        _productsCount[name].miningCount++;
        emit ProductMintBegin(msg.sender, name, tokenId);
    }

    function mintWithdraw(string calldata name, uint256 tokenId) external {
        IDNFTProduct p = _getProduct(name);
        Player storage player = _getPlayer(msg.sender);
        uint256 withdrawNum = p.mintWithdraw(msg.sender, tokenId);
        player.withdrawTotalValue += withdrawNum;
        _productsCount[name].withdrawCount++;
        _productsCount[name].withdrawSum += withdrawNum;
        emit ProductMintWithdraw(msg.sender, name, tokenId, withdrawNum);
    }

    function redeemProduct(string calldata name, uint256 tokenId) external {
        IDNFTProduct p = _getProduct(name);
        Player storage player = _getPlayer(msg.sender);
        uint256 withdrawNum = p.redeem(msg.sender, tokenId);
        player.withdrawTotalValue += withdrawNum;
        _productsCount[name].miningCount--;
        _productsCount[name].withdrawSum += withdrawNum;
        _productsCount[name].redeemedCount++;
        emit ProductMintRedeem(msg.sender, name, tokenId, withdrawNum);
    }

}