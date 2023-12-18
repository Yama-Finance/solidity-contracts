// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@beefy/contracts/interfaces/gmx/IGMXRouter.sol";
import "@beefy/contracts/interfaces/gmx/IBeefyVault.sol";
import "@beefy/contracts/interfaces/gmx/IGMXStrategy.sol";
import "@beefy/contracts/strategies/Common/StratFeeManagerInitializable.sol";

import "./PlvGlpCustodian.sol";

interface ICamelotRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;
}

/// @notice Forked from Beefy's GLP strategy
contract YPlvGlpStrategy is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    IERC20 public constant want = IERC20(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1); // plvGlp
    IERC20 public constant native = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F); // pls
    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant oldSGlp = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IERC20 public constant sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    // Third party contracts
    PlvGlpCustodian public custodian;
    ICamelotRouter public constant camelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    address public constant glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    IGMXRouter public constant gmxRouter = IGMXRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

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
        PlvGlpCustodian _custodian,
        bool _harvestOnDeposit
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        custodian = _custodian;
        harvestOnDeposit = _harvestOnDeposit;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            custodian.farm(uint96(wantBal));
        }
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            custodian.unfarm(uint96(_amount - wantBal));
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
        custodian.harvest();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 before = balanceOfWant();
            mintPlvGlp();

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

    // mint more PlvGlp with the ETH earned as fees
    function mintPlvGlp() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 1 ether) {
            address[] memory path = new address[](2);
            path[0] = address(native);
            path[1] = address(weth);
            camelotRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                nativeBal,
                0,
                path,
                address(this),
                address(this),
                block.timestamp
            );
            uint256 wethAmount = weth.balanceOf(address(this));
            gmxRouter.mintAndStakeGlp(address(weth), wethAmount, 0, 0);
            uint256 glpAmount = sGLP.balanceOf(address(this));
            if (glpAmount > 1 ether) {
                custodian.deposit(glpAmount);
                custodian.farm(uint96(balanceOfWant()));
            }
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return custodian.getFarmedAmount();
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return custodian.plutusChef().pendingRewards(address(custodian));
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

    // called as part of strat migration. Transfers all want (plvGlp) and GLP to new strat
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        address stratAddress = candidate.implementation;
        custodian.unfarm(uint96(balanceOfPool()));

        uint256 glpBal = sGLP.balanceOf(address(this));
        if (glpBal > 0) {
            sGLP.transfer(stratAddress, glpBal);
        }
        native.transfer(stratAddress, native.balanceOf(address(this)));
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
        IGMXStrategy(stratAddress).acceptTransfer();
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
        native.safeApprove(address(camelotRouter), type(uint).max);
        want.safeApprove(address(custodian), type(uint).max);
        weth.safeApprove(address(glpManager), type(uint).max);
        oldSGlp.safeApprove(address(custodian), type(uint).max);
    }

    function _removeAllowances() internal {
        native.safeApprove(address(camelotRouter), 0);
        want.safeApprove(address(custodian), 0);
        weth.safeApprove(address(glpManager), 0);
        oldSGlp.safeApprove(address(custodian), 0);
    }

    function acceptTransfer() external view {
        address prevStrat = IBeefyVault(vault).strategy();
        require(msg.sender == prevStrat, "!prevStrat");
        //gmxRouter.acceptTransfer(prevStrat);

        // send back 1 wei to complete upgrade
        //IERC20(want).safeTransfer(prevStrat, 1);
    }
}