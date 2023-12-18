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
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../jglp/JonesGlpSwapper.sol";
import "../jglp/JonesGlpMinter.sol";
import "./IMiniChef.sol";

contract YSJGlpStrategy is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    IERC20 public constant want = IERC20(0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6); // jGLP
    IERC20 public constant arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    // Third party contracts
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IRewardRouter public constant gmxRewardRouter = IRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    JonesGlpMinter public constant jonesMinter = JonesGlpMinter(0x59c8E540C7270A9Ba8D22cD9f90b5c376D998b97);
    IMiniChef public constant miniChef = IMiniChef(0x0aEfaD19aA454bCc1B1Dd86e18A7d58D0a6FAC38);
    address public constant glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

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
        uint256 amount = balanceOfWant();
        miniChef.deposit(poolId, amount, address(this));
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            miniChef.withdraw(poolId,  _amount - wantBal, address(this));
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
        callFeeRecipient; // silence unused variable compiler warning
        miniChef.harvest(poolId, address(this));
        uint256 arbBal = IERC20(arb).balanceOf(address(this));
        if (arbBal > 0) {
            //chargeFees(callFeeRecipient);
            uint256 before = balanceOfWant();
            convertAndDepositArb();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, before, balanceOfWant(), balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = IERC20(arb).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(arb).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(arb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(arb).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // mint more jGLP with the ARB earned as fees and re-deposit into the pool
    function convertAndDepositArb() internal {
        uint256 arbBal = IERC20(arb).balanceOf(address(this));
        if (arbBal > 0) {
            ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(arb, uint24(500), weth),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: arbBal,
                amountOutMinimum: 0
            });
            uint256 wethAmount = swapRouter.exactInput(params);
            try gmxRewardRouter.mintAndStakeGlp(address(weth), wethAmount, 0, 0) returns (uint256 glpAmount) {
                uint256 jGlpAmount = jonesMinter.depositGlp(glpAmount, true);
                miniChef.deposit(poolId, jGlpAmount, address(this));
            } catch {
                revert("YSJGlpStrategy: convertAndDepositArb failed");
            }
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
        return miniChef.userInfo(poolId, address(this)).amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return miniChef.pendingSushi(poolId, address(this));
    }

    // arb reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 arbBal = rewardsAvailable();

        return arbBal * fees.total / DIVISOR * fees.call / DIVISOR;
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

        miniChef.withdraw(poolId, balanceOfPool(), address(this));

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
        arb.safeApprove(address(swapRouter), type(uint).max);
        weth.safeApprove(glpManager, type(uint).max);
        sGLP.safeApprove(address(jonesMinter), type(uint).max);
        want.safeApprove(address(miniChef), type(uint).max);
    }

    function _removeAllowances() internal {
        arb.safeApprove(address(swapRouter), 0);
        weth.safeApprove(glpManager, 0);
        sGLP.safeApprove(address(jonesMinter), 0);
        want.safeApprove(address(miniChef), 0);
    }

    function acceptTransfer() external {
        //address prevStrat = IBeefyVault(vault).strategy();
        //require(msg.sender == prevStrat, "!prevStrat");
    }
}