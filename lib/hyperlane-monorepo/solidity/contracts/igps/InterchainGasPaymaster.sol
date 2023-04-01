// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ Internal Imports ============
import {IInterchainGasPaymaster} from "../../interfaces/IInterchainGasPaymaster.sol";
// ============ External Imports ============
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title InterchainGasPaymaster
 * @notice Manages payments on a source chain to cover gas costs of relaying
 * messages to destination chains.
 */
contract InterchainGasPaymaster is IInterchainGasPaymaster, OwnableUpgradeable {
    // ============ Events ============

    /**
     * @notice Emitted when a payment is made for a message's gas costs.
     * @param messageId The ID of the message to pay for.
     * @param gasAmount The amount of destination gas paid for.
     * @param payment The amount of native tokens paid.
     */
    event GasPayment(
        bytes32 indexed messageId,
        uint256 gasAmount,
        uint256 payment
    );

    // ============ Constructor ============

    constructor() {
        initialize(); // allows contract to be used without proxying
    }

    // ============ External Functions ============

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
     * @notice Deposits msg.value as a payment for the relaying of a message
     * to its destination chain.
     * @dev Overpayment will result in a refund of native tokens to the _refundAddress.
     * Callers should be aware that this may present reentrancy issues.
     * @param _messageId The ID of the message to pay for.
     * @param _destinationDomain The domain of the message's destination chain.
     * @param _gasAmount The amount of destination gas to pay for. Currently unused.
     * @param _refundAddress The address to refund any overpayment to. Currently unused.
     */
    function payForGas(
        bytes32 _messageId,
        uint32 _destinationDomain,
        uint256 _gasAmount,
        address _refundAddress
    ) external payable override {
        uint256 _requiredPayment = quoteGasPayment(
            _destinationDomain,
            _gasAmount
        );
        require(
            msg.value >= _requiredPayment,
            "insufficient interchain gas payment"
        );
        uint256 _overpayment = msg.value - _requiredPayment;
        if (_overpayment > 0) {
            (bool _success, ) = _refundAddress.call{value: _overpayment}("");
            require(_success, "Interchain gas payment refund failed");
        }

        emit GasPayment(_messageId, _gasAmount, msg.value);
    }

    /**
     * @notice Quotes the amount of native tokens to pay for interchain gas.
     * @param _destinationDomain The domain of the message's destination chain.
     * @param _gasAmount The amount of destination gas to pay for. Currently unused.
     * @return The amount of native tokens required to pay for interchain gas.
     */
    function quoteGasPayment(uint32 _destinationDomain, uint256 _gasAmount)
        public
        pure
        override
        returns (uint256)
    {
        // Silence compiler warning.
        _destinationDomain;
        _gasAmount;
        // Charge a flat 1 wei fee.
        // This is an intermediate step toward fully on-chain accurate gas payment quoting.
        return 1;
    }

    /**
     * @notice Transfers the entire native token balance to the owner of the contract.
     * @dev The owner must be able to receive native tokens.
     */
    function claim() external {
        // Transfer the entire balance to owner.
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "!transfer");
    }
}
