// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/Math.sol';

import '@openzeppelin/contracts/math/SafeMath.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '@openzeppelin/contracts/utils/Address.sol';

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract Boardroom is Ownable, ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant OPTION_LENGTH = 50;
    uint256 public period = 3 days;
    //uint256 public period = 30 minutes;

    IERC20 public paymentToken;

    uint256 public ownerRatio = 30;

    enum Status{
        NotExisting,
        Normal,
        Banned,
        Permitting
    }


    struct Record {
        bytes topic;
        bytes content;
        //总共有几个option
        uint256 optionNumber;
        //每个option的描述
        bytes[OPTION_LENGTH] options;
        //某一个选项总共收到了多少票
        uint256[OPTION_LENGTH] optionVotes;
        uint256 startTime;
        uint256 endTime;
        Status status;

        //选项的受益人
        address[OPTION_LENGTH] optionBeneficiaries;
        //总共收到了多少bird
        uint256 balance;

        //选项受益人是否已经打款
        bool optionBenefited;

    }


    Record[] public coreRecords;
    //record id => user => options[OPTION_LENGTH]
    mapping(uint256 => mapping(address => uint256[OPTION_LENGTH])) public coreCidAddressVotes;
    //record id => user => rewardGet
    mapping(uint256 => mapping(address => bool)) public coreCidAddressRewardGet;

    constructor(
        IERC20 _paymentToken
    ) public {
        paymentToken = _paymentToken;
    }

    function corePropose(
        bytes memory topic,
        bytes memory content,
        uint256 optionNumber,
        bytes[OPTION_LENGTH] memory options/*option的描述*/,
        uint256 startTime,
        address[OPTION_LENGTH] memory optionBeneficiaries
    ) onlyOwner public {
        require(optionNumber < OPTION_LENGTH, "optionNumber < OPTION_LENGTH");

        Record memory input = Record(
            topic,
            content,
            optionNumber,
            options,
            [uint256(0), 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            startTime,
            startTime + period,
            Status.Normal,
            optionBeneficiaries,
            uint256(0),
            false
        );
        coreRecords.push(input);
    }

    function coreUpdate(
        uint256 cid,
        bytes memory topic,
        bytes memory content,
        uint256 optionNumber,
        bytes[OPTION_LENGTH] memory options/*option的描述*/,
        address[OPTION_LENGTH] memory optionBeneficiaries
    ) onlyOwner public {
        Record storage record = coreRecords[cid];

        require(block.timestamp <= record.endTime, "block.timestamp <= record.endTime");
        require(record.status == Status.Normal, "The proposal does not exist");
        require(record.optionNumber <= optionNumber, "record.optionNumber <= optionNumber");
        record.topic = topic;
        record.content = content;
        record.optionNumber = optionNumber;
        record.options = options;
        record.optionBeneficiaries = optionBeneficiaries;
    }

    function coreBanned(uint256 cid) onlyOwner public {
        Record storage record = coreRecords[cid];
        require(record.status == Status.Normal, "The proposal does not exist");
        record.status = Status.Banned;
        record.topic = bytes("banned proposal");
        record.content = bytes("banned proposal");
        for (uint256 i = 0; i < OPTION_LENGTH; i++) {
            record.options[i] = bytes("banned proposal");
            record.optionBeneficiaries[i] = address(0);
        }
    }

    function coreVote(uint256 cid, uint256 optionIndex, uint256 amount) nonReentrant public {
        Record storage record = coreRecords[cid];
        require(record.startTime <= block.timestamp, "record.startTime <= block.timestamp");
        require(block.timestamp < record.endTime, "block.timestamp < record.endTime");
        require(record.status == Status.Normal, "The proposal has been banned");
        require(optionIndex < record.optionNumber, "optionIndex < record.optionNumber");

        uint256 balanceBefore = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = paymentToken.balanceOf(address(this));
        amount = balanceAfter.sub(balanceBefore);

        record.optionVotes[optionIndex] = record.optionVotes[optionIndex].add(amount);
        record.balance = record.balance.add(amount);

        //record id => user => options[OPTION_LENGTH]
        coreCidAddressVotes[cid][msg.sender][optionIndex] = coreCidAddressVotes[cid][msg.sender][optionIndex].add(amount);

    }

    function coreGetReward(uint256 cid) nonReentrant public {
        Record storage record = coreRecords[cid];

        require(record.endTime <= block.timestamp, "record.endTime <= block.timestamp");

        uint256 winOptionIndex = getCoreProposalWinOptionIndex(cid);

        if (record.optionBeneficiaries[winOptionIndex] == msg.sender && !record.optionBenefited) {
            record.optionBenefited = true;
            uint256 amount = record.balance.mul(ownerRatio).div(100);
            paymentToken.safeTransfer(msg.sender, amount);
        }

        if (!coreCidAddressRewardGet[cid][msg.sender] && coreCidAddressVotes[cid][msg.sender][winOptionIndex] != 0) {
            coreCidAddressRewardGet[cid][msg.sender] = true;
            uint256 totalBonus = record.balance.mul(uint256(100).sub(ownerRatio)).div(100);

            uint256 totalVotes = record.optionVotes[winOptionIndex];

            if (totalVotes == 0) {
                return;
            }

            uint256 msgSenderVotes = coreCidAddressVotes[cid][msg.sender][winOptionIndex];

            uint256 amount = totalBonus.mul(msgSenderVotes).div(totalVotes);

            if (amount > 0) {
                paymentToken.safeTransfer(msg.sender, amount);
            }
        }
    }

    function coreReward(uint256 cid, address account) external view returns(uint256 amount){
        Record storage record = coreRecords[cid];

        uint256 winOptionIndex = getCoreProposalWinOptionIndex(cid);

        amount = 0;

        if (record.optionBeneficiaries[winOptionIndex] == account && !record.optionBenefited) {
            amount = amount.add(record.balance.mul(ownerRatio).div(100));
        }

        if (!coreCidAddressRewardGet[cid][account] && coreCidAddressVotes[cid][account][winOptionIndex] != 0) {
            uint256 totalBonus = record.balance.mul(uint256(100).sub(ownerRatio)).div(100);

            uint256 totalVotes = record.optionVotes[winOptionIndex];

            if (totalVotes == 0) {
                return amount;
            }

            uint256 accountVotes = coreCidAddressVotes[cid][account][winOptionIndex];

            amount = amount.add(totalBonus.mul(accountVotes).div(totalVotes));
        }
        return amount;
    }

    function coreSendBalance(uint256 cid, uint256 amount) public {
        Record storage record = coreRecords[cid];
        require(record.startTime <= block.timestamp, "record.startTime <= block.timestamp");
        require(block.timestamp <= record.endTime, "block.timestamp <= record.endTime");
        require(record.status == Status.Normal, "The proposal has been banned");

        uint256 balanceBefore = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = paymentToken.balanceOf(address(this));
        amount = balanceAfter.sub(balanceBefore);

        record.balance = record.balance.add(amount);
    }

    function getCoreProposalWinOptionIndex(uint256 cid) public view returns (uint256 optionIndex) {
        Record storage record = coreRecords[cid];
        uint256 max = 0;
        optionIndex = 0;
        for (uint256 i = 0; i < record.optionNumber; i++) {

            if (max < record.optionVotes[i]) {
                max = record.optionVotes[i];
                optionIndex = i;
            }
        }
        return optionIndex;
    }

    function getCoreProposal(uint256 cid) view public returns (
        bytes memory topic,
        bytes memory content,
        uint256 optionNumber,
        bytes[OPTION_LENGTH] memory options,
        uint256[OPTION_LENGTH] memory optionVotes,
        uint256 startTime,
        uint256 endTime,
        Boardroom.Status status,
        address[OPTION_LENGTH] memory optionBeneficiaries,
        uint256 balance,
        bool optionBenefited
    ){
        Record storage record = coreRecords[cid];
        topic = record.topic;
        content = record.content;
        options = record.options;
        optionVotes = record.optionVotes;
        optionBeneficiaries = record.optionBeneficiaries;

        return (
        topic,
        content,
        record.optionNumber,
        options,
        optionVotes,
        record.startTime,
        record.endTime,
        record.status,
        optionBeneficiaries,
        record.balance,
        record.optionBenefited
        );
    }

    function getCoreVote(uint256 cid, address voter) view public returns (uint256[OPTION_LENGTH] memory){
        //mapping(uint256 => mapping(address => uint256[OPTION_LENGTH])) public coreCidAddressVotes;
        uint256[OPTION_LENGTH] storage votes = coreCidAddressVotes[cid][voter];
        return votes;
    }

    function getCoreProposals(uint256 skip, uint256 page, bool includeBanned, bool asc)
    public view returns (bytes[] memory topics, uint256[] memory pids, uint256[] memory deadlines){
        topics = new bytes[](page);
        pids = new uint256[](page);
        deadlines = new uint256[](page);

        uint256 retIndex = 0;
        if (asc) {
            uint256 start = skip;
            for (uint256 i = start; i < coreRecords.length && retIndex < page; i++) {
                Record storage record = coreRecords[i];
                if (!includeBanned && record.status == Status.Banned) {
                    continue;
                }
                topics[retIndex] = record.topic;
                pids[retIndex] = i;
                deadlines[retIndex] = record.endTime;

                retIndex++;
            }
        }
        else {
            uint256 start = coreRecords.length.sub(1).sub(skip);
            for (uint256 i = start; retIndex < page; i--) {
                Record storage record = coreRecords[i];
                if (!includeBanned && record.status == Status.Banned) {
                    continue;
                }
                topics[retIndex] = record.topic;
                pids[retIndex] = i;
                deadlines[retIndex] = record.endTime;

                retIndex++;
                if (i == 0) {
                    break;
                }
            }
        }
        return (topics, pids, deadlines);
    }

    function coreRecordsLength() external view returns (uint256){
        return coreRecords.length;
    }

    function changePayment(IERC20 _paymentToken) external onlyOwner {
        paymentToken = _paymentToken;
    }

    function changeConfig(uint256 _period) external onlyOwner {
        period = _period;
    }

    function changeOwnerRatio(uint256 _ownerRatio) external onlyOwner {
        ownerRatio = _ownerRatio;
    }
}
