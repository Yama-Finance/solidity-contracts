pub use primitive_types::{H128, H160, H256, H512, U128, U256, U512};

pub use announcement::*;
pub use chain_data::*;
pub use checkpoint::*;
pub use log_metadata::*;
pub use message::*;

use crate::{Decode, Encode, HyperlaneProtocolError};

mod announcement;
mod chain_data;
mod checkpoint;
mod log_metadata;
mod message;

/// Unified 32-byte identifier with convenience tooling for handling
/// 20-byte ids (e.g ethereum addresses)
pub mod identifiers;

/// A payment of native tokens for a message
#[derive(Debug)]
pub struct InterchainGasPayment {
    /// The id of the message
    pub message_id: H256,
    /// The payment amount, in origin chain native token wei
    pub payment: U256,
}

/// Uniquely identifying metadata for an InterchainGasPayment
#[derive(Debug)]
pub struct InterchainGasPaymentMeta {
    /// The transaction hash in which the GasPayment log was emitted
    pub transaction_hash: H256,
    /// The index of the GasPayment log within the transaction's logs
    pub log_index: U256,
}

impl Encode for InterchainGasPaymentMeta {
    fn write_to<W>(&self, writer: &mut W) -> std::io::Result<usize>
    where
        W: std::io::Write,
    {
        let mut written = 0;
        written += self.transaction_hash.write_to(writer)?;
        written += self.log_index.write_to(writer)?;
        Ok(written)
    }
}

impl Decode for InterchainGasPaymentMeta {
    fn read_from<R>(reader: &mut R) -> Result<Self, HyperlaneProtocolError>
    where
        R: std::io::Read,
        Self: Sized,
    {
        Ok(Self {
            transaction_hash: H256::read_from(reader)?,
            log_index: U256::read_from(reader)?,
        })
    }
}

/// An InterchainGasPayment with metadata to uniquely identify the payment
#[derive(Debug)]
pub struct InterchainGasPaymentWithMeta {
    /// The InterchainGasPayment
    pub payment: InterchainGasPayment,
    /// Metadata for the payment
    pub meta: InterchainGasPaymentMeta,
}

/// A cost estimate for a transaction.
#[derive(Clone, Debug, Default)]
pub struct TxCostEstimate {
    /// The gas limit for the transaction.
    pub gas_limit: U256,
    /// The gas price for the transaction.
    pub gas_price: U256,
}
