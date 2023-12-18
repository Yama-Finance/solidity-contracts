// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IMiniChef {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
        uint256 depositIncentives;
    }
    function deposit(uint256 _pid, uint256 _amount, address _to) external;

    function withdraw(uint256 _pid, uint256 _amount, address _to) external;

    function harvest(uint256 _pid, address _to) external;

    function userInfo(uint256 _pid, address _user) external view returns (
        UserInfo memory user);

    function poolInfo(uint256 _pid) external view returns (
        PoolInfo memory pool);
    
     /// @notice View function to see pending SUSHI on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SUSHI reward for a given user.
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
}