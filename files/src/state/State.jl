module State

using ..Types
using ..Messages: hash_block

# Simple in-memory state map. Later: Merkle/Verkle trie with proofs.
mutable struct StateDB
    accounts::Dict{Types.AccountID, Types.AccountState}
    state_root::Types.Hash
end

function StateDB()
    StateDB(Dict{Types.AccountID, Types.AccountState}(), UInt8[])
end

# Apply functions (no proofs here; v0.1 local)
function apply_send!(db::StateDB, blk::Types.SendBlock)
    sid = blk.header.account_id
    sst = get(db.accounts, sid, Types.AccountState(0, blk.header.prev_head, 0, nothing))
    @assert sst.head == blk.header.prev_head "Bad prev_head"
    @assert sst.balance >= blk.payload.amount "Insufficient balance"
    # Update sender
    sst = Types.AccountState(sst.balance - blk.payload.amount, hash_block(blk), sst.nonce + 1, sst.rep_id)
    db.accounts[sid] = sst
    # Record unspent transfer (simplified: add to recipient balance after receive)
    return true
end

function apply_receive!(db::StateDB, blk::Types.ReceiveBlock, amount::UInt128)
    rid = blk.header.account_id
    rst = get(db.accounts, rid, Types.AccountState(0, blk.header.prev_head, 0, nothing))
    @assert rst.head == blk.header.prev_head "Bad prev_head"
    # Credit recipient
    rst = Types.AccountState(rst.balance + amount, hash_block(blk), rst.nonce + 1, rst.rep_id)
    db.accounts[rid] = rst
    return true
end

end # module