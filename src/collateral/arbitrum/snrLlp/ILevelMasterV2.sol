// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface ILevelMasterV2 {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of REWARD entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of REWARD to distribute per block.
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
        bool staking;
    }
    
    function userInfo(uint256 pid, address user) external view returns (UserInfo memory);
    function poolInfo(uint256 pid) external view returns (PoolInfo memory);
    function harvest(uint256 pid, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function deposit(uint256 pid, uint256 amount, address to) external;
    function pendingReward(uint256 pid, address user) external view returns (uint256);
    function addLiquidity(
        uint256 pid,
        address assetToken,
        uint256 assetAmount,
        uint256 minLpAmount,
        address to
    ) external;
    function removeLiquidity(
        uint256 pid,
        uint256 lpAmount,
        address toToken,
        uint256 minOut,
        address to
    ) external;
}