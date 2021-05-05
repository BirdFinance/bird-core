// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './LPTokenWrapper.sol';

contract InvitationPool is LPTokenWrapper, Ownable
{
    IERC20 public token;
    uint256 constant public OneDay = 1 days;
    uint256 constant public Percent = 100;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    //note that, you should combine the bonus rate to get the final production rate
    uint256 public rewardRate = 0;
    //for inviter to get invitation bonus in target token
    uint256 public bonusRatio = 0;
    //for tax if you getReward, pay the ratio in source token
    uint256 public taxRatio = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public accumulatedRewards;
    mapping(address => address) public inviter;
    mapping(address => address[]) public invitees;
    mapping(address => uint256) public bonus;
    mapping(address => uint256) public accumulatedBonus;
    address public minerOwner;
    address public defaultInviter;
    address taxCollector;
    IERC20 public checkToken;

    address public feeManager;

    uint256 public fee = 0.004 ether;
    bool internal feeCharged = false;

    uint256 public withdrawCoolDown;
    //address => stake timestamp
    mapping(address => uint256) public withdrawCoolDownMap;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event BonusPaid(address indexed user, uint256 reward);
    event TransferBack(address token, address to, uint256 amount);

    constructor(
        address _token, //target
        address _lptoken, //source
        uint256 _starttime,
        address _minerOwner,
        address _defaultInviter,
        address _taxCollector,
        IERC20 _checkToken,
        address _feeManager,
        uint256 _withdrawCoolDown
    ) public {
        require(_token != address(0), "_token is zero address");
        require(_lptoken != address(0), "_lptoken is zero address");
        require(_minerOwner != address(0), "_minerOwner is zero address");

        token = IERC20(_token);
        lpt = IERC20(_lptoken);
        starttime = _starttime;
        minerOwner = _minerOwner;
        defaultInviter = _defaultInviter;
        taxCollector = _taxCollector;
        checkToken = _checkToken;
        feeManager = _feeManager;
        withdrawCoolDown = _withdrawCoolDown;
    }


    modifier checkStart() {
        require(block.timestamp >= starttime, 'Pool: not start');
        _;
    }

    modifier updateCoolDown(){
        withdrawCoolDownMap[msg.sender] = block.timestamp;
        _;
    }

    modifier checkCoolDown(){
        require(withdrawCoolDownMap[msg.sender].add(withdrawCoolDown) <= block.timestamp, "Cooling Down");
        _;
    }

    modifier updateInviter(address _inviter){
        address userInviter = inviter[msg.sender];
        if (userInviter == address(0)) {
            if (_inviter == address(0)) {
                inviter[msg.sender] = defaultInviter;
                //invitees[defaultInviter].push(msg.sender);
            } else {
                if (_inviter == msg.sender) {
                    _inviter = defaultInviter;
                }

                if(address(checkToken) != address (0)){
                    if (balanceOf(_inviter) == 0 && checkToken.balanceOf(_inviter) == 0) {
                        _inviter = defaultInviter;
                    }
                }

                inviter[msg.sender] = _inviter;
                invitees[_inviter].push(msg.sender);
            }
        } else {
            if (_inviter != address(0)) {
                require(userInviter == _inviter, "you can't change your inviter");
            }
        }
        _;
    }

    modifier chargeFee(){
        bool lock = false;
        if (!feeCharged) {
            require(msg.value >= fee, "msg.value >= minimumFee");
            payable(feeManager).transfer(msg.value);
            feeCharged = true;
            lock = true;
        }
        _;
        if (lock) {
            feeCharged = false;
        }
    }


    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable()
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    //008cc262
    function earned(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
        .div(1e18)
        .add(rewards[account]);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    //7acb7757
    function stake(uint256 amount, address _inviter)
    public
    payable
    updateReward(msg.sender)
    checkStart
    updateInviter(_inviter)
    chargeFee
    updateCoolDown
    {
        require(amount > 0, 'Pool: Cannot stake 0');
        super.lpStake(amount);
        emit Staked(msg.sender, amount);
    }

    //2e1a7d4d1
    function withdraw(uint256 amount)
    public
    payable
    updateReward(msg.sender)
    checkStart
    chargeFee
    checkCoolDown
    {
        require(amount > 0, 'Pool: Cannot withdraw 0');
        super.lpWithdraw(amount);

        if (isTaxOn()) {
            clearReward();
        }

        emit Withdrawn(msg.sender, amount);
    }

    //e9fad8ee
    function exit() external payable chargeFee checkCoolDown {
        getReward();
        getBonus();
        withdraw(balanceOf(msg.sender));
    }

    //3d18b912
    function getReward() public payable updateReward(msg.sender) checkStart chargeFee {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            token.safeTransferFrom(minerOwner, msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
            accumulatedRewards[msg.sender] = accumulatedRewards[msg.sender].add(reward);

            address userInviter = inviter[msg.sender];
            uint256 userBonus = reward.mul(bonusRatio).div(Percent);
            bonus[userInviter] = bonus[userInviter].add(userBonus);

            if (isTaxOn()) {
                uint256 amount = balanceOf(msg.sender).mul(taxRatio).div(Percent);
                lpPayTax(amount, taxCollector);
            }
        }
    }

    function clearReward() internal updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
        }
    }

    //8bdff161
    function getBonus() public payable checkStart chargeFee {
        uint256 userBonus = bonus[msg.sender];
        if (userBonus > 0) {
            bonus[msg.sender] = 0;
            token.safeTransferFrom(minerOwner, msg.sender, userBonus);
            emit BonusPaid(msg.sender, userBonus);
            accumulatedBonus[msg.sender] = accumulatedBonus[msg.sender].add(userBonus);
        }
    }

    //0eb88e5
    function getRewardAndBonus() external payable chargeFee {
        getReward();
        getBonus();
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(erc20Token != lpt, "For LPT, transferBack is not allowed, if you transfer LPT by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
        emit TransferBack(address(erc20Token), to, amount);
    }

    function isTaxOn() internal view returns (bool){
        return taxRatio != 0;
    }

    function initSet(uint256 _starttime, uint256 rewardPerDay, uint256 _bonusRatio, uint256 _taxRatio, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {

        require(block.timestamp < starttime, "block.timestamp < starttime");

        require(block.timestamp < _starttime, "block.timestamp < _starttime");
        require(_starttime < _periodFinish, "_starttime < _periodFinish");

        starttime = _starttime;
        rewardRate = rewardPerDay.div(OneDay);
        bonusRatio = _bonusRatio;
        taxRatio = _taxRatio;
        periodFinish = _periodFinish;
        lastUpdateTime = starttime;
    }

    function updateRewardRate(uint256 rewardPerDay, uint256 _bonusRatio, uint256 _taxRatio, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {
        if (_periodFinish == 0) {
            _periodFinish = block.timestamp;
        }

        require(starttime < block.timestamp, "starttime < block.timestamp");
        require(block.timestamp <= _periodFinish, "block.timestamp <= _periodFinish");

        rewardRate = rewardPerDay.div(OneDay);
        bonusRatio = _bonusRatio;
        taxRatio = _taxRatio;
        periodFinish = _periodFinish;
        lastUpdateTime = block.timestamp;
    }

    function changeDefaultInviter(address _defaultInviter) external onlyOwner {
        defaultInviter = _defaultInviter;
    }

    function changeBonusRatio(uint256 _bonusRatio) external onlyOwner {
        bonusRatio = _bonusRatio;
    }

    function changeMinerOwner(address _minerOwner) external onlyOwner {
        minerOwner = _minerOwner;
    }

    function changeTaxCollector(address _taxCollector) external onlyOwner {
        taxCollector = _taxCollector;
    }

    function changeFee(
        uint256 _fee,
        address _feeManager
    ) external onlyOwner {
        fee = _fee;
        feeManager = _feeManager;
    }

    function changeWithdrawCoolDown(uint256 _withdrawCoolDown) external onlyOwner{
        withdrawCoolDown = _withdrawCoolDown;
    }

    function changeCheckToken(IERC20 _checkToken) external onlyOwner{
        checkToken = _checkToken;
    }
}
