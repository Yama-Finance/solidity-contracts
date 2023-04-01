use std::collections::HashMap;

use eyre::{eyre, Context, Result};
use sea_orm::{prelude::*, ActiveValue::*, DeriveColumn, EnumIter, Insert, NotSet, QuerySelect};
use tracing::{instrument, trace};

use hyperlane_core::{TxnInfo, H256, U256};

use crate::conversions::{format_h256, parse_h256};
use crate::date_time;
use crate::db::ScraperDb;

use super::generated::transaction;

#[derive(Debug, Clone)]
pub struct StorableTxn {
    pub info: TxnInfo,
    pub block_id: i64,
}

impl ScraperDb {
    /// Lookup transactions and find their ids. Any transactions which are not
    /// found be excluded from the hashmap.
    pub async fn get_txn_ids(
        &self,
        hashes: impl Iterator<Item = &H256>,
    ) -> Result<HashMap<H256, i64>> {
        #[derive(Copy, Clone, Debug, EnumIter, DeriveColumn)]
        enum QueryAs {
            Id,
            Hash,
        }

        // check database to see which txns we already know and fetch their IDs
        transaction::Entity::find()
            .filter(transaction::Column::Hash.is_in(hashes.map(format_h256)))
            .select_only()
            .column_as(transaction::Column::Id, QueryAs::Id)
            .column_as(transaction::Column::Hash, QueryAs::Hash)
            .into_values::<(i64, String), QueryAs>()
            .all(&self.0)
            .await
            .context("When fetching transactions")?
            .into_iter()
            .map(|(id, hash)| Ok((parse_h256(hash)?, id)))
            .collect::<Result<_>>()
    }

    /// Store a new transaction into the database (or update an existing one).
    #[instrument(skip_all)]
    pub async fn store_txns(&self, txns: impl Iterator<Item = StorableTxn>) -> Result<i64> {
        let as_f64 = U256::to_f64_lossy;
        let models = txns
            .map(|txn| {
                let receipt = txn
                    .receipt
                    .as_ref()
                    .ok_or_else(|| eyre!("Transaction is not yet included"))?;

                Ok(transaction::ActiveModel {
                    id: NotSet,
                    block_id: Unchanged(txn.block_id),
                    gas_limit: Set(as_f64(txn.gas_limit)),
                    max_priority_fee_per_gas: Set(txn.max_priority_fee_per_gas.map(as_f64)),
                    hash: Unchanged(format_h256(&txn.hash)),
                    time_created: Set(date_time::now()),
                    gas_used: Set(as_f64(receipt.gas_used)),
                    gas_price: Set(txn.gas_price.map(as_f64)),
                    effective_gas_price: Set(receipt.effective_gas_price.map(as_f64)),
                    nonce: Set(txn.nonce as i64),
                    sender: Set(format_h256(&txn.sender)),
                    recipient: Set(txn.recipient.as_ref().map(format_h256)),
                    max_fee_per_gas: Set(txn.max_fee_per_gas.map(as_f64)),
                    cumulative_gas_used: Set(as_f64(receipt.cumulative_gas_used)),
                })
            })
            .collect::<Result<Vec<_>>>()?;

        debug_assert!(!models.is_empty());
        trace!(?models, "Writing txns to database");
        // this is actually the ID that was first inserted for postgres
        let first_id = Insert::many(models).exec(&self.0).await?.last_insert_id;
        Ok(first_id)
    }
}
