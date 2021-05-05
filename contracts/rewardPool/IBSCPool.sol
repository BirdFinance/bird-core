// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.8.0;

interface IBSCPool {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pending(uint256 _pid, address _user) external view returns (uint256);

    function userInfo(uint256 _pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 _pid) external view returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accMdxPerShare, uint256 accMultLpPerShare, uint256 totalAmount);

    function emergencyWithdraw(uint256 pid) external;

    function poolLength() external view returns (uint256);

    function mdxPerBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);
}
