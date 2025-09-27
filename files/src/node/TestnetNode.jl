module TestnetNode

using ..Types
using ..State
using ..RateLimiter
using ..CommitteeSelection
using ..Aggregation
using ..Messages: hash_block, block_to_canonical_json
using Base: Set, time_ns
using Dates
using SHA

export NodeConfig, InMemoryNode, register_account!, submit_payment!, get_account_balance
export list_blocks, list_quorum_certs, metrics_snapshot, memory_breakdown, projected_capacity

const ZERO_HASH = fill(UInt8(0x00), 32)
const EST_ACCOUNT_BYTES = 256
const EST_BLOCK_BYTES = 640
const EST_QUORUM_BYTES = 512
const EST_PAYMENT_BYTES = 2 * EST_BLOCK_BYTES + 2 * EST_QUORUM_BYTES

mutable struct NodeMetrics
    start_wallclock::DateTime
    start_monotonic_ns::Int
    total_payments::Int
    total_latency_ns::Int
    last_latency_ns::Int
    last_payment_at::Union{Nothing,DateTime}
end

function NodeMetrics()
    NodeMetrics(now(), time_ns(), 0, 0, 0, nothing)
end

struct NodeConfig
    committee_size::Int
    threshold::Int
    epoch_seed::UInt64
end

NodeConfig(; committee_size::Int=8, threshold::Int=5, epoch_seed::UInt64=UInt64(0)) =
    NodeConfig(committee_size, threshold, epoch_seed)

mutable struct InMemoryNode
    config::NodeConfig
    state::State.StateDB
    limiter::RateLimiter.Limiter
    members::Set{Types.AccountID}
    blocks::Vector{Types.AbstractBlock}
    quorum_certs::Vector{Types.QuorumCert}
    epoch::UInt64
    metrics::NodeMetrics
end

function InMemoryNode(config::NodeConfig=NodeConfig())
    db = State.StateDB()
    db.state_root = copy(ZERO_HASH)
    InMemoryNode(config, db, RateLimiter.Limiter(), Set{Types.AccountID}(), Types.AbstractBlock[], Types.QuorumCert[], config.epoch_seed, NodeMetrics())
end

function reset_metrics!(node::InMemoryNode)
    node.metrics = NodeMetrics()
end

function record_payment_metrics!(node::InMemoryNode, latency_ns::Integer, timestamp::DateTime)
    metrics = node.metrics
    latency = latency_ns > typemax(Int) ? typemax(Int) : Int(latency_ns)
    metrics.total_payments += 1
    metrics.total_latency_ns += latency
    metrics.last_latency_ns = latency
    metrics.last_payment_at = timestamp
end

function register_account!(node::InMemoryNode, account_id::Types.AccountID; initial_balance::UInt128=UInt128(0))
    if haskey(node.state.accounts, account_id)
        error("Account $(account_id) already exists")
    end
    node.state.accounts[account_id] = Types.AccountState(initial_balance, copy(ZERO_HASH), UInt64(0), nothing)
    push!(node.members, account_id)
    return account_id
end

function get_account_balance(node::InMemoryNode, account_id::Types.AccountID)
    haskey(node.state.accounts, account_id) || error("Unknown account $(account_id)")
    return node.state.accounts[account_id].balance
end

function build_signature(parts...)
    bytes = codeunits(join(string.(parts)))
    sig = SHA.sha512(bytes)
    return collect(sig)
end

function generate_committee(node::InMemoryNode, account::Types.AccountID, seq::UInt64)
    members_vec = collect(node.members)
    members_vec == [] && error("No registered members available for committee selection")
    committee, index_map = CommitteeSelection.select_committee(
        members_vec;
        committee_size=node.config.committee_size,
        epoch=node.epoch,
        account=account,
        seq=seq
    )
    return committee, index_map
end

function generate_qc(node::InMemoryNode, block::Types.AbstractBlock, committee, index_map)
    blk_hash = hash_block(block)
    votes = Types.PartialVote[]
    for member in committee.members
        idx = index_map[member]
        signature = SHA.sha256(vcat(blk_hash, codeunits(member)))
        push!(votes, Types.PartialVote(blk_hash, node.epoch, committee.id, member, idx, collect(signature)))
    end
    effective_threshold = min(node.config.threshold, length(committee.members))
    qc = Aggregation.aggregate_qc(votes, committee, effective_threshold)
    qc === nothing && error("Failed to reach quorum for block")
    push!(node.quorum_certs, qc)
    push!(node.blocks, block)
    node.epoch += 1
    return qc
end

function update_state_root!(node::InMemoryNode, block::Types.AbstractBlock)
    node.state.state_root = hash_block(block)
end

function submit_payment!(node::InMemoryNode, from::Types.AccountID, to::Types.AccountID, amount::UInt128)
    start_ns = time_ns()
    amount == 0 && error("Amount must be positive")
    haskey(node.state.accounts, from) || error("Unknown sender $(from)")
    haskey(node.state.accounts, to) || error("Unknown recipient $(to)")
    from == to && error("Sender and recipient must differ")
    RateLimiter.rate_limit_check!(node.limiter, from) || error("Rate limit exceeded for $(from)")

    sender_state = node.state.accounts[from]
    recipient_state = node.state.accounts[to]
    sender_state.balance >= amount || error("Insufficient balance for $(from)")

    timestamp = now()
    transfer_id = collect(SHA.sha256(codeunits(string(from, to, amount, timestamp))))
    payload_hash = collect(SHA.sha256(vcat(transfer_id, codeunits(string(amount)))))

    send_header = Types.BlockHeader(
        from,
        copy(sender_state.head),
        sender_state.nonce + 1,
        copy(node.state.state_root),
        sender_state.nonce + 1,
        timestamp,
        payload_hash
    )
    send_payload = Types.SendPayload(to, amount, transfer_id)
    send_sig = build_signature(from, to, amount, timestamp)
    send_block = Types.SendBlock(send_header, send_payload, send_sig)
    State.apply_send!(node.state, send_block)
    committee, index_map = generate_committee(node, from, send_header.height)
    send_qc = generate_qc(node, send_block, committee, index_map)
    update_state_root!(node, send_block)

    recv_header = Types.BlockHeader(
        to,
        copy(recipient_state.head),
        recipient_state.nonce + 1,
        copy(node.state.state_root),
        recipient_state.nonce + 1,
        timestamp,
        payload_hash
    )
    recv_payload = Types.ReceivePayload(from, transfer_id)
    recv_sig = build_signature(to, from, amount, timestamp)
    receive_block = Types.ReceiveBlock(recv_header, recv_payload, recv_sig)
    State.apply_receive!(node.state, receive_block, amount)
    committee_recv, index_map_recv = generate_committee(node, to, recv_header.height)
    recv_qc = generate_qc(node, receive_block, committee_recv, index_map_recv)
    update_state_root!(node, receive_block)

    elapsed_ns = time_ns() - start_ns
    record_payment_metrics!(node, elapsed_ns, timestamp)

    return (; send_block, receive_block, send_qc, recv_qc)
end

function list_blocks(node::InMemoryNode; canonical::Bool=true)
    return canonical ? [block_to_canonical_json(block) for block in node.blocks] : node.blocks
end

function list_quorum_certs(node::InMemoryNode)
    return node.quorum_certs
end

function memory_breakdown(node::InMemoryNode)
    account_bytes = EST_ACCOUNT_BYTES * length(node.state.accounts)
    block_bytes = EST_BLOCK_BYTES * length(node.blocks)
    qc_bytes = EST_QUORUM_BYTES * length(node.quorum_certs)
    total_bytes = account_bytes + block_bytes + qc_bytes
    return (; total_bytes, account_bytes, block_bytes, qc_bytes)
end

function projected_capacity(node::InMemoryNode, mem_limit_gb::Real)
    mem_limit_gb <= 0 && error("Memory limit must be positive")
    breakdown = memory_breakdown(node)
    limit_bytes = Int(floor(mem_limit_gb * 1024^3))
    remaining_bytes = max(0, limit_bytes - breakdown.total_bytes)
    per_payment_bytes = max(1, EST_PAYMENT_BYTES)
    additional_payments = remaining_bytes ÷ per_payment_bytes
    return (; mem_limit_gb=Float64(mem_limit_gb), limit_bytes, remaining_bytes, additional_payments)
end

function metrics_snapshot(node::InMemoryNode; mem_limits=(4.0, 8.0))
    metrics = node.metrics
    elapsed_ns = max(1, time_ns() - metrics.start_monotonic_ns)
    uptime_seconds = elapsed_ns / 1.0e9
    avg_latency_ms = metrics.total_payments == 0 ? 0.0 : (metrics.total_latency_ns / metrics.total_payments) / 1.0e6
    last_latency_ms = metrics.last_latency_ns == 0 ? 0.0 : metrics.last_latency_ns / 1.0e6
    throughput = metrics.total_payments == 0 ? 0.0 : metrics.total_payments / uptime_seconds
    mem = memory_breakdown(node)
    projections = [projected_capacity(node, limit) for limit in mem_limits]
    return (
        total_payments = metrics.total_payments,
        avg_latency_ms = avg_latency_ms,
        last_latency_ms = last_latency_ms,
        uptime_seconds = uptime_seconds,
        throughput_tps = throughput,
        last_payment_at = metrics.last_payment_at,
        memory = mem,
        projections = projections
    )
end

end # module
