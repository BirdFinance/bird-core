// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './OldLPTokenWrapper.sol';

contract OldPool is OldLPTokenWrapper, Ownable
{
    IERC20 public token;
    uint256 constant public OneDay = 1 days;
    uint256 constant public Percent = 100;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    //note that, you should combine the bonus rate to get the final production rate
    uint256 public rewardRate = 0;
    //for inviter to get invitation bonus
    uint256 public bonusRatio = 0;
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

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event BonusPaid(address indexed user, uint256 reward);
    event TransferBack(address token, address to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(
        address _token,
        address _lptoken,
        uint256 _starttime,
        address _minerOwner,
        address _defaultInviter
    ) public {
        require(_token != address(0), "_token is zero address");
        require(_lptoken != address(0), "_lptoken is zero address");
        require(_minerOwner != address(0), "_minerOwner is zero address");

        token = IERC20(_token);
        lpt = IERC20(_lptoken);
        starttime = _starttime;
        minerOwner = _minerOwner;
        defaultInviter = _defaultInviter;
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

    modifier checkStart() {
        require(block.timestamp >= starttime, 'Pool: not start');
        _;
    }

    modifier updateInviter(address _inviter){
        address userInviter = inviter[msg.sender];
        if (userInviter == address(0)) {
            if (_inviter == address(0)) {
                inviter[msg.sender] = defaultInviter;
                //invitees[defaultInviter].push(msg.sender);
            } else {
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

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
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

    function earned(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
        .div(1e18)
        .add(rewards[account]);
    }

    function stake(uint256 amount, address _inviter)
    public
    updateReward(msg.sender)
    checkStart
    updateInviter(_inviter)
    {
        require(amount > 0, 'Pool: Cannot stake 0');
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
    public
    override
    updateReward(msg.sender)
    checkStart
    {
        require(amount > 0, 'Pool: Cannot withdraw 0');
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();

    }

    //hook the bonus when user getReward
    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            token.safeTransferFrom(minerOwner, msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
            accumulatedRewards[msg.sender] = accumulatedRewards[msg.sender].add(reward);

            address userInviter = inviter[msg.sender];
            uint256 userBonus = reward.mul(bonusRatio).div(Percent);
            bonus[userInviter] = bonus[userInviter].add(userBonus);
        }
    }

    function getBonus() public checkStart {
        uint256 userBonus = bonus[msg.sender];
        if (userBonus > 0) {
            bonus[msg.sender] = 0;
            token.safeTransferFrom(minerOwner, msg.sender, userBonus);
            emit BonusPaid(msg.sender, userBonus);
            accumulatedBonus[msg.sender] = accumulatedBonus[msg.sender].add(userBonus);
        }
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


    //you can call this function many time as long as block.number does not reach starttime and _starttime
    function initSet(uint256 _starttime, uint256 rewardPerDay, uint256 _bonusRatio, uint256 _periodFinish)
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
        periodFinish = _periodFinish;
        lastUpdateTime = starttime;
    }

    function updateRewardRate(uint256 rewardPerDay, uint256 _bonusRatio, uint256 _periodFinish)
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
        require(_minerOwner != address(0), "new owner should not be the zero address");
        emit OwnershipTransferred(minerOwner, _minerOwner);
        minerOwner = _minerOwner;
    }
}
