//! Bitcoin block and its components.
//!
//! The data is expected to be prepared in advance and passed as program arguments.

use utils::hash::Digest;
use utils::double_sha256::double_sha256_u32_array;
use utils::numeric::u32_byte_reverse;
use super::transaction::Transaction;
use core::fmt::{Display, Formatter, Error};

/// Represents a block in the blockchain.
#[derive(Drop, Copy, Debug, PartialEq, Default, Serde)]
pub struct Block {
    /// Block header.
    pub header: Header,
    /// Transaction data: either merkle root or list of transactions.
    pub data: TransactionData,
}

/// Represents block contents.
#[derive(Drop, Copy, Debug, PartialEq, Serde)]
pub enum TransactionData {
    /// Merkle root of all transactions in the block.
    /// This variant is used for header-only validation mode (light client).
    MerkleRoot: Digest,
    /// List of all transactions included in the block.
    /// This variant is used for the full consensus validation mode.
    Transactions: Span<Transaction>,
}

/// Represents a block header.
/// https://learnmeabitcoin.com/technical/block/
///
/// NOTE that some of the fields are missing, that's intended.
/// The point of the client is to calculate next chain state from the previous
/// chain state and block data in a provable way.
/// The proof can be later used to verify that the chain state is valid.
/// In order to do the calculation we just need data about the block that is strictly necessary,
/// but not the data we can calculate like merkle root or data that we already have
/// like previous_block_hash (in the previous chain state).
#[derive(Drop, Copy, Debug, PartialEq, Default, Serde)]
pub struct Header {
    /// Hash of the block.
    pub hash: Digest,
    /// The version of the block.
    pub version: u32,
    /// The timestamp of the block.
    pub time: u32,
    /// The difficulty target for mining the block.
    /// Not strictly necessary since it can be computed from target,
    /// but it is cheaper to validate than compute.
    pub bits: u32,
    /// The nonce used in mining the block.
    pub nonce: u32,
}

#[generate_trait]
pub impl BlockHashImpl of BlockHash {
    /// Checks if the block hash is valid by re-computing it given the missing fields.
    fn validate_hash(
        self: @Header, prev_block_hash: Digest, merkle_root: Digest
    ) -> Result<(), ByteArray> {
        let mut header_data_u32: Array<u32> = array![];

        header_data_u32.append(u32_byte_reverse(*self.version));
        header_data_u32.append_span(prev_block_hash.value.span());
        header_data_u32.append_span(merkle_root.value.span());

        header_data_u32.append(u32_byte_reverse(*self.time));
        header_data_u32.append(u32_byte_reverse(*self.bits));
        header_data_u32.append(u32_byte_reverse(*self.nonce));

        let hash = double_sha256_u32_array(header_data_u32);

        if *self.hash == hash {
            Result::Ok(())
        } else {
            Result::Err("Invalid block hash")
        }
    }
}

/// Empty transaction data
pub impl TransactionDataDefault of Default<TransactionData> {
    fn default() -> TransactionData {
        TransactionData::Transactions(array![].span())
    }
}

impl BlockDisplay of Display<Block> {
    fn fmt(self: @Block, ref f: Formatter) -> Result<(), Error> {
        let data = match *self.data {
            TransactionData::MerkleRoot(root) => format!("{}", root),
            TransactionData::Transactions(txs) => format!("{}", txs.len())
        };
        let str: ByteArray = format!(" Block {{ header: {}, data: {} }}", *self.header, @data);
        f.buffer.append(@str);
        Result::Ok(())
    }
}

impl HeaderDisplay of Display<Header> {
    fn fmt(self: @Header, ref f: Formatter) -> Result<(), Error> {
        let str: ByteArray = format!(
            "Header {{ hash: {}, version: {}, time: {}, bits: {}, nonce: {}}}",
            *self.hash,
            *self.version,
            *self.time,
            *self.bits,
            *self.nonce
        );
        f.buffer.append(@str);
        Result::Ok(())
    }
}

impl TransactionDataDisplay of Display<TransactionData> {
    fn fmt(self: @TransactionData, ref f: Formatter) -> Result<(), Error> {
        match *self {
            TransactionData::MerkleRoot(root) => f.buffer.append(@format!("MerkleRoot: {}", root)),
            TransactionData::Transactions(txs) => f
                .buffer
                .append(@format!("Transactions: {}", txs.len()))
        };
        Result::Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{Header, BlockHash};
    use crate::types::chain_state::ChainState;
    use utils::hash::Digest;
    use utils::hex::hex_to_hash_rev;

    #[test]
    fn test_block_hash() {
        let mut chain_state: ChainState = Default::default();
        chain_state
            .best_block_hash =
                0x000000002a22cfee1f2c846adbd12b3e183d4f97683f85dad08a79780a84bd55_u256
            .into();
        // block 170
        let header = Header {
            hash: hex_to_hash_rev(
                "00000000d1145790a8694403d4063f323d499e655c83426834d4ce2f8dd4a2ee"
            ),
            version: 1_u32,
            time: 1231731025_u32,
            bits: 0x1d00ffff_u32,
            nonce: 1889418792_u32
        };
        let merkle_root: Digest =
            0x7dac2c5666815c17a3b36427de37bb9d2e2c5ccec3f8633eb91a4205cb4c10ff_u256
            .into();

        let result = header.validate_hash(chain_state.best_block_hash, merkle_root);
        assert!(result.is_ok());
    }

    #[test]
    fn test_merkle_root_diff() {
        let mut chain_state: ChainState = Default::default();
        chain_state
            .best_block_hash =
                0x000000002a22cfee1f2c846adbd12b3e183d4f97683f85dad08a79780a84bd55_u256
            .into();
        // block 170
        let header = Header {
            hash: hex_to_hash_rev(
                "00000000d1145790a8694403d4063f323d499e655c83426834d4ce2f8dd4a2ee"
            ),
            version: 1_u32,
            time: 1231731025_u32,
            bits: 0x1d00ffff_u32,
            nonce: 1889418792_u32
        };
        let merkle_root: Digest =
            0x6dac2c5666815c17a3b36427de37bb9d2e2c5ccec3f8633eb91a4205cb4c10ff_u256
            .into();

        let result = header.validate_hash(chain_state.best_block_hash, merkle_root);
        assert!(result.is_err());
    }

    #[test]
    fn test_best_block_hash_diff() {
        let mut chain_state: ChainState = Default::default();
        chain_state
            .best_block_hash =
                0x000000002a22cfee1f2c846adbd12b3e183d4f97683f85dad08a79780a84bd56_u256
            .into();
        // block 170
        let header = Header {
            hash: hex_to_hash_rev(
                "00000000d1145790a8694403d4063f323d499e655c83426834d4ce2f8dd4a2ee"
            ),
            version: 1_u32,
            time: 1231731025_u32,
            bits: 0x1d00ffff_u32,
            nonce: 1889418792_u32
        };
        let merkle_root: Digest =
            0x7dac2c5666815c17a3b36427de37bb9d2e2c5ccec3f8633eb91a4205cb4c10ff_u256
            .into();

        let result = header.validate_hash(chain_state.best_block_hash, merkle_root);
        assert!(result.is_err());
    }
}
