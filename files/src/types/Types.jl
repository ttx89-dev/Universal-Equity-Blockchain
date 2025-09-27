module Types

using Dates

# Basic aliases
const Hash = Vector{UInt8}
const AccountID = String  # v0.1: PoP ID or pubkey hash as string

# Headers and payloads
struct BlockHeader
    account_id::AccountID
    prev_head::Hash
    height::UInt64
    state_root_hint::Hash
    nonce::UInt64
    timestamp::DateTime
    payload_hash::Hash
end

struct SendPayload
    to_account::AccountID
    amount::UInt128
    transfer_id::Hash
end

struct ReceivePayload
    from_account::AccountID
    transfer_id::Hash
end

abstract type AbstractBlock end

struct SendBlock <: AbstractBlock
    header::BlockHeader
    payload::SendPayload
    sig::Vector{UInt8} # ed25519
end

struct ReceiveBlock <: AbstractBlock
    header::BlockHeader
    payload::ReceivePayload
    sig::Vector{UInt8}
end

# Consensus types
struct Committee
    epoch::UInt64
    id::String
    members::Vector{AccountID}
end

struct CommitteeMember
    id::AccountID
    bitmap_index::Int
end

struct PartialVote
    block_hash::Hash
    committee_epoch::UInt64
    committee_id::String
    member_id::AccountID
    bitmap_index::Int
    partial_sig::Vector{UInt8}
end

struct QuorumCert
    block_hash::Hash
    committee_epoch::UInt64
    committee_id::String
    bitmap::BitVector
    agg_sig::Vector{UInt8}      # v0.1: concatenate partials or store separately
    threshold::Int
end

# Account state
struct AccountState
    balance::UInt128
    head::Hash
    nonce::UInt64
    rep_id::Union{Nothing,AccountID}
end

end # module