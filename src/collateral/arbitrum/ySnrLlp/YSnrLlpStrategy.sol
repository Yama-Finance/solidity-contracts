// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@beefy/contracts/interfaces/gmx/IGMXRouter.sol";
import "@beefy/contracts/interfaces/gmx/IGMXTracker.sol";
import "@beefy/contracts/interfaces/gmx/IGLPManager.sol";
import "@beefy/contracts/interfaces/gmx/IGMXVault.sol";
import "@beefy/contracts/interfaces/gmx/IBeefyVault.sol";
import "@beefy/contracts/interfaces/gmx/IGMXStrategy.sol";
import "@beefy/contracts/strategies/Common/StratFeeManagerInitializable.sol";
import "../snrLlp/ILevelMasterV2.sol";

interface ILBRouter {
     /**
     * @dev The path parameters, such as:
     * - pairBinSteps: The list of bin steps of the pairs to go through
     * - versions: The list of versions of the pairs to go through
     * - tokenPath: The list of tokens in the path to go through
     */
    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        IERC20[] tokenPath;
    }

    /**
     * @dev This enum represents the version of the pair requested
     * - V1: Joe V1 pair
     * - V2: LB pair V2. Also called legacyPair
     * - V2_1: LB pair V2.1 (current version)
     */
    enum Version {
        V1,
        V2,
        V2_1
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

contract YSnrLlpStrategy is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    IERC20 public constant want = IERC20(0x5573405636F4b895E511C9C54aAfbefa0E7Ee458); // snrLlp
    IERC20 public constant native = IERC20(0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149); // lvl
    IERC20 public constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    // Third party contracts
    ILBRouter public constant swapRouter = ILBRouter(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);
    ILevelMasterV2 public constant levelMaster = ILevelMasterV2(0x0180dee5Df18eBF76642e50FaaEF426f7b2874f7);

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public constant poolId = 0;
    uint256 public constant ACC_REWARD_PRECISION = 1e12;

    event StratHarvest(
        address indexed harvester,
        uint256 oldWantBal,
        uint256 newWantBal,
        uint256 tvl
    );
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        CommonAddresses calldata _commonAddresses,
        bool _harvestOnDeposit
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        harvestOnDeposit = _harvestOnDeposit;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        levelMaster.deposit(poolId, balanceOfWant(), address(this));
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            levelMaster.withdraw(poolId,  _amount - wantBal, address(this));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        levelMaster.harvest(poolId, address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 before = balanceOfWant();
            convertAndDepositLvl();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, before, balanceOfWant(), balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // mint more snrLlp with the LVL earned as fees and re-deposit into the pool
    function convertAndDepositLvl() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            IERC20[] memory tokenPath = new IERC20[](2);
            tokenPath[0] = native;
            tokenPath[1] = usdt;

            uint256[] memory pairBinSteps = new uint256[](1);
            pairBinSteps[0] = 30;

            ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);
            versions[0] = ILBRouter.Version.V1;

            ILBRouter.Path memory path; // instantiate and populate the path to perform the swap.
            path.pairBinSteps = pairBinSteps;
            path.versions = versions;
            path.tokenPath = tokenPath;

            uint256 usdtAmount = swapRouter.swapExactTokensForTokens(
                nativeBal,
                0,
                path,
                address(this),
                block.timestamp
            );
            levelMaster.addLiquidity(
                poolId,
                address(usdt),
                usdtAmount,
                0,
                address(this)
            );
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return levelMaster.userInfo(poolId, address(this)).amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return levelMaster.pendingReward(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = rewardsAvailable();

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Transfers all want to new strat.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        levelMaster.withdraw(poolId, balanceOfPool(), address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();
    }

    function _giveAllowances() internal {
        native.safeApprove(address(swapRouter), type(uint).max);
        usdt.safeApprove(address(levelMaster), type(uint).max);
        want.safeApprove(address(levelMaster), type(uint).max);
    }

    function _removeAllowances() internal {
        native.safeApprove(address(swapRouter), 0);
        usdt.safeApprove(address(levelMaster), 0);
        want.safeApprove(address(levelMaster), 0);
    }

    function acceptTransfer() external {
        //address prevStrat = IBeefyVault(vault).strategy();
        //require(msg.sender == prevStrat, "!prevStrat");
    }
}