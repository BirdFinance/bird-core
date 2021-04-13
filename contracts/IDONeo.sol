// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract IDONeo is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public redeemTime;

    IERC20 public sourceToken;
    //总的提供的份数, immutable
    uint256 public totalSupply;
    //当前剩余的总份数
    uint256 public currentSupply;

    //为了校验,记录Org[>1]的所有supply
    uint256 internal nonPublicSupply;

    struct Organisation {
        //start from 1
        uint256 id;

        //需要多少sourceToken购买
        uint256 price;
        //购买的份数,通常是1,可以设定为2,3,4....
        uint256 copy;
        //总配额份数,可以是1+1+1..也可以是2+2+2...
        //对id=0的public,是totalSupply-其他org supply的剩余
        uint256 supply;
        //剩余配额份数
        uint256 currentSupply;

        uint256 checkTokenMinimum;

        string memo;

        //白名单,只要在白名单内,可以享受Org的价格,但是超过了supply,只能fallback到id 0的public
        mapping(address => bool) whiteList;

    }

    mapping(uint256 => Organisation) public organisationRegistry;

    //记录所有人购买的份数
    mapping(address => uint256) public purchasedCopy;

    //记录是否已经提取
    mapping(address => bool) public purchasedRedeemed;

    //记录所有已购买的地址
    address[] public purchasedCopyList;

    //地址属于哪个Org
    mapping(address => uint256) public accountRegistry;

    IERC20 public checkToken;
    //===============================
    //兑现期用的参数
    IERC20 public targetToken;
    //每份对应的targetToken
    uint256 public targetTokenFactor;

    //===============================
    //费用
    uint256 public purchaseFee = 0.00001 ether;
    address public feeManager;
    bool public pause;

    event Purchase(address indexed buyer, uint256 price, uint256 copy, uint256 orgId);
    event Redeem(address indexed buyer, uint256 amount);
    event Disqualification(address indexed buyer, uint256 copy);

    constructor(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _redeemTime,
        IERC20 _sourceToken,
        uint256 _publicPrice,
        uint256 _publicCopy,
        uint256 _totalSupply,
        IERC20 _checkToken,
        uint256 _publicCheckTokenMinimum,
        IERC20 _targetToken,
        uint256 _targetTokenFactor,
        address _feeManager
    ) public {
        require(_startTime < _endTime, "_startTime < _endTime");
        require(_endTime < _redeemTime, "_endTime< _redeemTime");
        startTime = _startTime;
        endTime = _endTime;
        redeemTime = _redeemTime;

        sourceToken = _sourceToken;

        totalSupply = _totalSupply;
        currentSupply = _totalSupply;

        checkToken = _checkToken;

        targetToken = _targetToken;
        targetTokenFactor = _targetTokenFactor;

        //prepare public
        Organisation storage org = organisationRegistry[0];
        org.id = 0;
        org.price = _publicPrice;
        org.copy = _publicCopy;
        org.supply = 0;
        org.currentSupply = 0;
        org.checkTokenMinimum = _publicCheckTokenMinimum;
        org.memo = "public";

        feeManager = _feeManager;
    }

    modifier inPurchase(){
        require(startTime <= block.timestamp, "IDO has not started");
        require(block.timestamp < endTime, "IDO has end");
        _;
    }

    modifier inRedeem(){
        require(redeemTime <= block.timestamp, "Redeem has not started");
        require(address(targetToken) != address(0), "Target token addres not set");
        require(targetTokenFactor > 0, "targetTokenMultiplicationFactor should not be zero");
        _;
    }

    modifier notPause(){
        require(!pause, "pause");
        _;
    }

    modifier chargeFee(){
        require(msg.value >= purchaseFee);
        payable(feeManager).transfer(msg.value);
        _;
    }

    function isRedeemAble(address account) external view returns (uint256 redeemAmount, bool redeemed){
        if (redeemTime > block.timestamp) {
            return (0, false);
        }
        if (address(targetToken) == address(0)) {
            return (0, false);
        }
        if (targetTokenFactor == 0) {
            return (0, false);
        }

        if (purchasedCopy[account] == 0) {
            if (purchasedRedeemed[account] == true) {
                return (0, true);
            }
            return (0, false);
        }
        return (purchasedCopy[account].mul(targetTokenFactor), false);
    }

    function purchase() inPurchase chargeFee nonReentrant notPause payable external {
        require(purchasedCopy[msg.sender] == 0, "you bought");

        (uint256 id,uint256 price) = filter(msg.sender);
        Organisation storage org = organisationRegistry[id];

        if (address(checkToken) != address(0)) {
            require(checkToken.balanceOf(msg.sender) >= org.checkTokenMinimum, "checkTokenMinimum");
        }

        if (id != 0) {
            org.currentSupply = org.currentSupply.sub(org.copy);
        }
        currentSupply = currentSupply.sub(org.copy);

        purchasedCopy[msg.sender] = purchasedCopy[msg.sender].add(org.copy);
        purchasedCopyList.push(msg.sender);
        sourceToken.safeTransferFrom(msg.sender, address(this), price);

        emit Purchase(msg.sender, price, org.copy, id);

    }

    function filter(address account) public view returns (uint256 id, uint256 price){
        id = accountRegistry[account];

        if (id != 0) {
            Organisation storage org = organisationRegistry[id];
            if (org.currentSupply >= org.copy) {
                //enough, return organisation price
                return (id, org.price);
            }
        }

        Organisation storage org0 = organisationRegistry[0];
        return (0, org0.price);
    }

    function redeem() inRedeem chargeFee nonReentrant notPause payable external {
        uint256 copy = purchasedCopy[msg.sender];
        require(copy > 0, "you didn't buy, or you have redeemed");
        uint256 amount = copy.mul(targetTokenFactor);

        targetToken.safeTransfer(msg.sender, amount);
        purchasedCopy[msg.sender] = 0;
        purchasedRedeemed[msg.sender] = true;

        emit Redeem(msg.sender, amount);
    }

    function disqualify(address account) onlyOwner external {

        uint256 copy = purchasedCopy[account];
        purchasedCopy[account] = 0;
        emit Disqualification(account, copy);
    }

    function setOrganisation(
        uint256 _id,
        uint256 _price,
        uint256 _copy,
        uint256 _supply,
        uint256 _checkTokenMinimum,
        address[] calldata _whiteList,
        string calldata _memo
    )
    external onlyOwner {
        require(_id > 0, "_id > 0");
        require(organisationRegistry[_id].id == 0, "registered");

        require(nonPublicSupply.add(_supply) <= totalSupply, "nonPublicSupply.add(_supply) <= totalSupply");
        nonPublicSupply = nonPublicSupply.add(_supply);

        Organisation storage org = organisationRegistry[_id];
        org.id = _id;
        org.price = _price;
        org.copy = _copy;
        org.supply = _supply;
        org.currentSupply = _supply;
        org.checkTokenMinimum = _checkTokenMinimum;
        org.memo = _memo;
        for (uint256 i = 0; i < _whiteList.length; i ++) {
            org.whiteList[_whiteList[i]] = true;
            accountRegistry[_whiteList[i]] = _id;
        }
    }


    function setWhiteList(uint256 _id, address[] calldata _whiteList) external onlyOwner {
        Organisation storage org = organisationRegistry[_id];
        for (uint256 i = 0; i < _whiteList.length; i ++) {
            if (accountRegistry[_whiteList[i]] > 0) {
                //已经设定过某一个org了,跳过,不能属于2个org
                continue;
            }
            org.whiteList[_whiteList[i]] = true;
            accountRegistry[_whiteList[i]] = _id;
        }
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

    function initSet(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _redeemTime
    ) onlyOwner external {
        require(block.timestamp < startTime, "updateConfig must happens before it starts");


        require(block.timestamp < _startTime, "new startTime must not before now");
        require(_startTime < _endTime, "_startTime < _endTime");
        require(_endTime < _redeemTime, "_endTime < _redeemTime");

        startTime = _startTime;
        endTime = _endTime;
        redeemTime = _redeemTime;
    }

    function updateConfig(
        uint256 _endTime,
        uint256 _redeemTime
    ) onlyOwner external {
        require(block.timestamp < endTime, "updateConfig must happens before it ends");

        if (_endTime == 0) {
            _endTime = block.timestamp;
        }

        require(block.timestamp <= _endTime, "new endTime must not before now");
        require(startTime < _endTime, "_startTime < _endTime");
        require(_endTime < _redeemTime, "_endTime < _redeemTime");

        endTime = _endTime;
        redeemTime = _redeemTime;
    }

    function changeRedeemTime(uint256 _redeemTime) onlyOwner external {
        if (_redeemTime == uint256(0)) {
            _redeemTime = block.timestamp;
        }
        require(endTime < _redeemTime, "endTime < _redeemTime");
        redeemTime = _redeemTime;
    }

    function changeFee(address _feeManager, uint256 _purchaseFee) onlyOwner external {
        feeManager = _feeManager;
        purchaseFee = _purchaseFee;
    }

    function purchasedCopyListLength() view external returns (uint256){
        return purchasedCopyList.length;
    }

    function setPause(bool _pause) onlyOwner external {
        pause = _pause;
    }
}
