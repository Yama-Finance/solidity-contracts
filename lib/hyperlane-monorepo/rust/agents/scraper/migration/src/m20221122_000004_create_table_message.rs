use crate::l20221122_types::*;
use crate::m20221122_000001_create_table_domain::Domain;
use crate::m20221122_000003_create_table_transaction::Transaction;
use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Message::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Message::Id)
                            .big_integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(
                        ColumnDef::new(Message::TimeCreated)
                            .timestamp()
                            .not_null()
                            .default("NOW()"),
                    )
                    .col(
                        ColumnDef::new_with_type(Message::MsgId, Hash)
                            .not_null()
                            .unique_key(),
                    )
                    .col(ColumnDef::new(Message::Origin).unsigned().not_null())
                    .col(ColumnDef::new(Message::Destination).unsigned().not_null())
                    .col(ColumnDef::new(Message::Nonce).unsigned().not_null())
                    .col(ColumnDef::new_with_type(Message::Sender, Address).not_null())
                    .col(ColumnDef::new_with_type(Message::Recipient, Address).not_null())
                    .col(ColumnDef::new(Message::MsgBody).binary())
                    .col(ColumnDef::new_with_type(Message::OriginMailbox, Address).not_null())
                    .col(ColumnDef::new(Message::Timestamp).timestamp().not_null())
                    .col(ColumnDef::new(Message::OriginTxId).big_integer().not_null())
                    .foreign_key(
                        ForeignKey::create()
                            .from_col(Message::Origin)
                            .to(Domain::Table, Domain::Id),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .from_col(Message::OriginTxId)
                            .to(Transaction::Table, Transaction::Id),
                    )
                    .index(
                        Index::create()
                            .unique()
                            .col(Message::OriginMailbox)
                            .col(Message::Origin)
                            .col(Message::Nonce),
                    )
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .table(Message::Table)
                    .name("msg_tx_timestamp")
                    .col(Message::Timestamp)
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .table(Message::Table)
                    .name("message_tx_idx")
                    .col(Message::OriginTxId)
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .table(Message::Table)
                    .name("message_sender_idx")
                    .col(Message::Sender)
                    .index_type(IndexType::Hash)
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .table(Message::Table)
                    .name("message_recipient_idx")
                    .col(Message::Recipient)
                    .index_type(IndexType::Hash)
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .table(Message::Table)
                    .name("message_msg_id_idx")
                    .col(Message::MsgId)
                    .index_type(IndexType::Hash)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Message::Table).to_owned())
            .await
    }
}

/// Learn more at https://docs.rs/sea-query#iden
#[derive(Iden)]
pub enum Message {
    Table,
    /// Unique database ID
    Id,
    /// Time of record creation
    TimeCreated,
    /// Unique id of the message on the blockchain
    MsgId,
    /// Domain ID of the origin chain
    Origin,
    /// Domain ID of the destination chain
    Destination,
    /// Nonce of this message in the merkle tree of the mailbox
    Nonce,
    /// Address of the message sender on the origin chain (not necessarily the
    /// transaction signer)
    Sender,
    /// Address of the message recipient on the destination chain.
    Recipient,
    /// Binary blob included in the message.
    MsgBody,
    /// Address of the mailbox contract which sent the message.
    OriginMailbox,
    /// timestamp on block that includes the origin transaction (saves a double
    /// join)
    Timestamp,
    /// Transaction this message was dispatched in on the origin chain.
    OriginTxId,
}
