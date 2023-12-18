// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./IPlutusChef.sol";
import "./IPlvGlpDepositor.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/modules/templates/YSSModule.sol";

/// @notice Custodies plvGLP for the Yama protocol
contract PlvGlpCustodian is YSSModule {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;

    IERC20 public oldSGlp = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IERC20 public sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IPlutusChef public plutusChef = IPlutusChef(0x4E5Cf54FdE5E1237e80E87fcbA555d829e1307CE);
    IERC4626 public plvGlp = IERC4626(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    IPlvGlpDepositor public plvGLPDepositor = IPlvGlpDepositor(0xEAE85745232983CF117692a1CE2ECf3d19aDA683);
    IERC20 public pls = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
    mapping(address account => bool isAuthorized) public authorized;

    constructor(YSS _stablecoin) YSSModule(_stablecoin) {}

    /// @notice Checks if the caller is authorized
    modifier onlyAuthorized() {
        require(authorized[msg.sender], "YPlvGlpCustodian: Not authorized");
        _;
    }

    /// @notice Sets the addressess of the contracts
    function setAddresses(
        IERC20 _oldSGlp,
        IERC20 _sGLP,
        IPlutusChef _plutusChef,
        IERC4626 _plvGlp,
        IPlvGlpDepositor _plvGLPDepositor,
        IERC20 _pls
    ) external onlyAllowlist {
        oldSGlp = _oldSGlp;
        sGLP = _sGLP;
        plutusChef = _plutusChef;
        plvGlp = _plvGlp;
        plvGLPDepositor = _plvGLPDepositor;
        pls = _pls;
    }

    /// @notice Sets the authorization status of an account
    function setAuthorized(address account, bool isAuthorized) external onlyAllowlist {
        authorized[account] = isAuthorized;
    }

    /// @notice Deposits oldSGlp into the PlvDepositor contract for PlvGlp
    function deposit(uint256 _amount) external onlyAuthorized {
        oldSGlp.safeTransferFrom(msg.sender, address(this), _amount);
        oldSGlp.safeApprove(address(plvGLPDepositor), _amount);
        plvGLPDepositor.deposit(_amount);
        plvGlp.safeTransfer(msg.sender, plvGlp.balanceOf(address(this)));
    }

    /// @notice Withdraws oldSGlp from the PlvDepositor contract
    function redeem(uint256 _amount) external onlyAuthorized {
        plvGlp.safeTransferFrom(msg.sender, address(this), _amount);
        plvGlp.safeApprove(address(plvGLPDepositor), _amount);
        plvGLPDepositor.redeem(_amount);
        sGLP.safeTransfer(msg.sender, sGLP.balanceOf(address(this)));
    }

    /// @notice Deposits plvGLP into the PlutusChef contract
    function farm(uint96 _amount) external onlyAuthorized {
        plvGlp.safeTransferFrom(msg.sender, address(this), _amount);
        plvGlp.safeApprove(address(plutusChef), _amount);
        plutusChef.deposit(_amount);
    }

    /// @notice Withdraws plvGLP from the PlutusChef contract
    function unfarm(uint96 _amount) external onlyAuthorized {
        plutusChef.withdraw(_amount);
        plvGlp.safeTransfer(msg.sender, _amount);
    }

    /// @notice Withdraws all plvGLP from the PlutusChef contract
    function emergencyWithdraw() external onlyAuthorized {
        plutusChef.emergencyWithdraw();
        plvGlp.safeTransfer(msg.sender, plvGlp.balanceOf(address(this)));
    }

    /// @notice Harvests PLS rewards from the PlutusChef contract
    function harvest() external onlyAuthorized {
        plutusChef.harvest();
        pls.safeTransfer(msg.sender, pls.balanceOf(address(this)));
    }

    /// @notice Gets the amount of plvGLP deposited into the PlutusChef contract
    function getFarmedAmount() external view returns (uint256) {
        (uint256 amount, ) = plutusChef.userInfo(address(this));
        return amount;
    }

    /// @notice Used by allowlist contracts to transfer tokens out
    /// @param token The token to transfer
    /// @param to The recipient
    /// @param amount The amount to transfer
    function transfer(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyAllowlist {
        token.safeTransfer(to, amount);
    }
}