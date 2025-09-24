
using SHA
using Dates
using Random
using UUIDs

"""aequchain.jl

aequchain — Universal Equidistributed Blockchain (aequchain)

Summary
- Implementation of a demonstration Universal Equidistributed Blockchain (UEB) with exact monetary
  precision using Rational{BigInt}.
- Supports global member coins, networks, businesses, pledges (including recurring business pledges),
  a small immutable transaction/block structure, and a demo runner.

Purpose
- Provide a reference/demo implementation focused on exact equality distribution semantics,
  safety checks (30-day spend limits), and multi-network business/pledge flows.
- Intended for testing, experimentation, and documentation; not for production use (see DEMO_MODE).

Quick usage
- Load the file in Julia and call `run_demo()` to exercise the demo flows.
- Use provided functions to init_treasury, join_member, create_network, create_business,
  create_pledge, support_pledge, etc.

Notes & Caveats
- DEMO_MODE = true: no persistence, simplified recurring behavior, and supervisory checks.
- Monetary values are represented as Rational{BigInt} with cent precision.
- This file includes a minimal blockchain log (blocks with SHA-256 hashes) for auditability only.

License & Attribution
- Add appropriate license and attribution in the repository root as needed.

Example
- julia --project -e 'include("aequchain.jl"); aequchain.run_demo()'

"""
# ============================================================================
# UNIVERSAL EQUIDISTRIBUTED BLOCKCHAIN (aequchain) - Exact Precision
# Merges UEB/EDS: Global equality, multi-network, safety; uses Rational for exact math
# ============================================================================
const DEMO_MODE = true  # Safe for testing; no persistence

# Core Data Structures (Using Rational{BigInt} for exact monetary precision)
# ============================================================================
mutable struct Treasury
    stable_coins::Rational{BigInt}  # Total stablecoins (global, exact)
    peg_currency::String
    peg_rate::Rational{BigInt}
    
    Treasury() = new(0//1, "USD", 1//1)
end

mutable struct MemberCoin
    owner::String
    minted_at::DateTime
    
    MemberCoin(owner::String) = new(owner, now())
end

mutable struct Network
    id::String
    name::String
    denomination::String
    denom_rate::Rational{BigInt}  # Denom units per stablecoin
    members::Set{String}
    businesses::Dict{String, String}  # business_id => owner
    created_at::DateTime
    
    Network(id::String, name::String, denom::String, rate::Float64) = new(id, name, denom, Rational{BigInt}(BigInt(trunc(rate * 100)), BigInt(100)), Set{String}(), Dict{String, String}(), now())  # Approx to rational
end

mutable struct Member
    id::String
    networks::Set{String}  # Multiple networks allowed
    businesses_owned::Set{String}
    businesses_employed::Set{String}
    joined_at::DateTime
    total_30_day_spend::Rational{BigInt}
    spend_history::Vector{Tuple{DateTime, Rational{BigInt}, String}}  # (time, amount, type)
    contrib_rate::Rational{BigInt}  # Enterprise contribution (0-5/100)
    
    Member(id::String) = new(id, Set{String}(), Set{String}(), Set{String}(), now(), 0//1, Vector{Tuple{DateTime, Rational{BigInt}, String}}(), 0//1)
end

mutable struct Business
    id::String
    name::String
    owner::String
    network_id::String
    contrib_rate::Rational{BigInt}  # 0-5/100
    employees::Set{String}
    alloc_budget::Rational{BigInt}  # Spending allocation
    created_at::DateTime
    
    Business(id::String, name::String, owner::String, network::String) = new(id, name, owner, network, 0//1, Set{String}(), 0//1, now())
end

mutable struct Pledge
    id::String
    name::String
    creator::String
    network_id::String
    target::Rational{BigInt}
    current::Rational{BigInt}
    supporters::Dict{String, Rational{BigInt}}
    purpose::String
    is_business::Bool  # True for business (e.g., startup/funding)
    recurring::Bool  # Monthly recurring (business only)
    monthly_amount::Rational{BigInt}  # For recurring
    completed::Bool
    created_at::DateTime
    
    Pledge(id::String, name::String, creator::String, network::String, target::Float64, purpose::String, is_business::Bool, recurring::Bool=false, monthly::Float64=0.0) = 
        new(id, name, creator, network, Rational{BigInt}(BigInt(trunc(target * 100)), BigInt(100)), 0//1, Dict{String, Rational{BigInt}}(), purpose, is_business, recurring && is_business, Rational{BigInt}(BigInt(trunc(monthly * 100)), BigInt(100)), false, now())
end

struct Transaction
    id::String
    type::String
    from::String
    to::String
    data::Dict{String, Any}
    timestamp::DateTime
    
    Transaction(type::String, from::String, to::String, data::Dict{String, Any}) = new(string(uuid4()), type, from, to, data, now())
end

mutable struct Block
    hash::String
    prev_hash::String
    transaction::Transaction
    timestamp::DateTime
    validator::String
    
    Block(prev_hash::String, transaction::Transaction, validator::String) = new("", prev_hash, transaction, now(), validator)
end

# Global State
# ============================================================================
mutable struct BlockchainState
    treasury::Treasury
    member_coins::Dict{String, MemberCoin}  # Global non-transferable coins
    networks::Dict{String, Network}
    members::Dict{String, Member}
    businesses::Dict{String, Business}
    pledges::Dict{String, Pledge}
    blockchain::Vector{Block}
    avg_contrib_rate::Rational{BigInt}  # Network-wide average
    
    BlockchainState() = new(Treasury(), Dict{String, MemberCoin}(), Dict{String, Network}(), Dict{String, Member}(), Dict{String, Business}(), Dict{String, Pledge}(), Vector{Block}(), 0//1)
end

const BLOCKCHAIN = BlockchainState()

# Helper Functions
# ============================================================================
function create_block_hash(block::Block)
    return bytes2hex(sha256(string(block.prev_hash, block.transaction.id, block.timestamp, block.validator)))
end

function add_transaction(tx::Transaction, validator::String)
    prev_hash = isempty(BLOCKCHAIN.blockchain) ? "0" : BLOCKCHAIN.blockchain[end].hash
    block = Block(prev_hash, tx, validator)
    block.hash = create_block_hash(block)
    push!(BLOCKCHAIN.blockchain, block)
    println("✅ Transaction: $(tx.type)")
end

function get_total_members()
    return length(BLOCKCHAIN.member_coins)  # Global count
end

function get_member_coin_value()
    num_members = get_total_members()
    return num_members > 0 ? BLOCKCHAIN.treasury.stable_coins // num_members : 0//1
end

function get_treasury_value()
    return BLOCKCHAIN.treasury.stable_coins * BLOCKCHAIN.treasury.peg_rate
end

# Safety & Spending
# ============================================================================
function clean_spend_history(member_id::String)
    member = BLOCKCHAIN.members[member_id]
    cutoff = now() - Day(30)
    member.spend_history = filter(r -> r[1] > cutoff, member.spend_history)
    member.total_30_day_spend = sum(r[2] for r in member.spend_history; init=0//1)
end

function get_spend_allowance(member_id::String)
    clean_spend_history(member_id)
    value = get_member_coin_value()
    member = BLOCKCHAIN.members[member_id]
    return max(0//1, value - member.total_30_day_spend)  # 30-day limit = exact equal share
end

function validate_spend(member_id::String, amount::Rational{BigInt}, typ::String)
    allowance = get_spend_allowance(member_id)
    if amount > allowance
        error("🛡️ Limit exceeded: $amount > $allowance (30-day)")
    end
    return true
end

function record_spend(member_id::String, amount::Rational{BigInt}, typ::String)
    member = BLOCKCHAIN.members[member_id]
    push!(member.spend_history, (now(), amount, typ))
    member.total_30_day_spend += amount
end

# Initialization & Membership
# ============================================================================
function init_treasury(deposit::Float64, currency::String, rate::Float64, founder::String)
    dep_rat = Rational{BigInt}(BigInt(trunc(deposit * 100)), BigInt(100))
    rate_rat = Rational{BigInt}(BigInt(trunc(rate * 100)), BigInt(100))
    stable = dep_rat // rate_rat
    BLOCKCHAIN.treasury.stable_coins = stable
    BLOCKCHAIN.treasury.peg_currency = currency
    BLOCKCHAIN.treasury.peg_rate = rate_rat
    BLOCKCHAIN.members[founder] = Member(founder)
    BLOCKCHAIN.member_coins[founder] = MemberCoin(founder)
    
    data = Dict("deposit" => dep_rat, "stable" => stable, "currency" => currency, "rate" => rate_rat, "founder" => founder, "value" => get_member_coin_value())
    tx = Transaction("INIT_TREASURY", "SYSTEM", founder, data)
    add_transaction(tx, founder)
    
    println("✅ Treasury initialized: $stable stablecoins (exact)")
end

function join_member(id::String, deposit::Float64)
    if haskey(BLOCKCHAIN.member_coins, id)
        error("Member exists")
    end
    members = get_total_members()
    required = members > 0 ? get_treasury_value() // members : 0//1
    dep_rat = Rational{BigInt}(BigInt(trunc(deposit * 100)), BigInt(100))
    if abs(dep_rat - required) > 1//100  # Tolerance for input
        error("Required: $required, provided: $dep_rat")
    end
    stable = dep_rat // BLOCKCHAIN.treasury.peg_rate
    BLOCKCHAIN.treasury.stable_coins += stable
    BLOCKCHAIN.members[id] = Member(id)
    BLOCKCHAIN.member_coins[id] = MemberCoin(id)
    
    data = Dict("member" => id, "deposit" => dep_rat, "stable" => stable, "total_members" => members + 1, "value" => get_member_coin_value())
    tx = Transaction("JOIN_MEMBER", id, "TREASURY", data)
    add_transaction(tx, id)
    
    println("✅ Member $id joined: value $(get_member_coin_value()) (exact)")
end

function exit_member(id::String)
    if !haskey(BLOCKCHAIN.member_coins, id)
        error("Member not found")
    end
    if get_total_members() == 1
        error("Last member")
    end
    value = get_member_coin_value()
    refund_stable = value
    refund = refund_stable * BLOCKCHAIN.treasury.peg_rate
    BLOCKCHAIN.treasury.stable_coins -= refund_stable
    delete!(BLOCKCHAIN.member_coins, id)
    delete!(BLOCKCHAIN.members, id)
    
    data = Dict("member" => id, "refund" => refund, "new_value" => get_member_coin_value())
    tx = Transaction("EXIT_MEMBER", id, "TREASURY", data)
    add_transaction(tx, first(keys(BLOCKCHAIN.member_coins)))
    
    println("✅ Member $id exited: refund $refund (exact)")
    return refund
end

# Transfers (Meaningless for Equality)
# ============================================================================
function transfer(from::String, to::String, amount::Float64)
    if !haskey(BLOCKCHAIN.member_coins, from) || !haskey(BLOCKCHAIN.member_coins, to)
        error("Members not found")
    end
    amt_rat = Rational{BigInt}(BigInt(trunc(amount * 100)), BigInt(100))
    data = Dict("from" => from, "to" => to, "amount" => amt_rat, "value_before" => get_member_coin_value(), "value_after" => get_member_coin_value(), "equality" => true)
    tx = Transaction("TRANSFER", from, to, data)
    add_transaction(tx, from)
    println("✅ Transfer logged: equality preserved (exact)")
end

# Networks
# ============================================================================
function create_network(name::String, denom::String, rate::Float64, creator::String)
    if !haskey(BLOCKCHAIN.member_coins, creator)
        error("Member only")
    end
    id = string(uuid4())
    net = Network(id, name, denom, rate)
    BLOCKCHAIN.networks[id] = net
    push!(net.members, creator)
    push!(BLOCKCHAIN.members[creator].networks, id)
    
    data = Dict("id" => id, "name" => name, "denom" => denom, "rate" => net.denom_rate, "creator" => creator)
    tx = Transaction("CREATE_NETWORK", creator, "SYSTEM", data)
    add_transaction(tx, creator)
    
    println("✅ Network $name created")
    return id
end

function join_network(member_id::String, net_id::String)
    if !haskey(BLOCKCHAIN.member_coins, member_id) || !haskey(BLOCKCHAIN.networks, net_id)
        error("Not found")
    end
    net = BLOCKCHAIN.networks[net_id]
    member = BLOCKCHAIN.members[member_id]
    push!(net.members, member_id)
    push!(member.networks, net_id)
    
    data = Dict{String, Any}("member" => member_id, "net_id" => net_id)
    tx = Transaction("JOIN_NETWORK", member_id, net_id, data)
    add_transaction(tx, member_id)
    
    println("✅ $member_id joined $net_id")
end

function get_member_denom_value(member_id::String, net_id::String)
    net = BLOCKCHAIN.networks[net_id]
    return get_member_coin_value() * net.denom_rate
end

# Businesses & Contributions
# ============================================================================
function create_business(name::String, owner::String, net_id::String)
    if !haskey(BLOCKCHAIN.member_coins, owner) || !haskey(BLOCKCHAIN.networks, net_id)
        error("Requirements not met")
    end
    net = BLOCKCHAIN.networks[net_id]
    if !(owner in net.members)
        error("Owner must join network")
    end
    id = string(uuid4())
    bus = Business(id, name, owner, net_id)
    BLOCKCHAIN.businesses[id] = bus
    net.businesses[id] = owner
    push!(BLOCKCHAIN.members[owner].businesses_owned, id)
    
    data = Dict{String, Any}("id" => id, "name" => name, "owner" => owner, "net_id" => net_id)
    tx = Transaction("CREATE_BUSINESS", owner, id, data)
    add_transaction(tx, owner)
    
    println("✅ Business $name created")
    return id
end

function set_contrib_rate(bus_id::String, rate::Float64, owner::String)
    bus = BLOCKCHAIN.businesses[bus_id]
    rate_rat = Rational{BigInt}(BigInt(trunc(rate * 10000)), BigInt(10000))  # Precise to 4 decimals
    if bus.owner != owner || rate_rat < 0//1 || rate_rat > 5//100
        error("Invalid")
    end
    bus.contrib_rate = rate_rat
    recalc_avg_contrib()
    
    data = Dict("bus_id" => bus_id, "rate" => rate_rat, "avg" => BLOCKCHAIN.avg_contrib_rate)
    tx = Transaction("SET_CONTRIB", owner, bus_id, data)
    add_transaction(tx, owner)
    
    println("✅ Contrib rate: $rate_rat")
end

function recalc_avg_contrib()
    total_bus = length(BLOCKCHAIN.businesses)
    if total_bus == 0
        BLOCKCHAIN.avg_contrib_rate = 0//1
        return
    end
    total_rate = sum(b.contrib_rate for b in values(BLOCKCHAIN.businesses); init=0//1)
    BLOCKCHAIN.avg_contrib_rate = total_rate // total_bus
end

function business_spend(bus_id::String, amount::Float64, purpose::String, owner::String)
    bus = BLOCKCHAIN.businesses[bus_id]
    amt_rat = Rational{BigInt}(BigInt(trunc(amount * 100)), BigInt(100))
    if bus.owner != owner || amt_rat > bus.alloc_budget
        error("Invalid")
    end
    validate_spend(owner, amt_rat, "BUSINESS")
    BLOCKCHAIN.treasury.stable_coins -= amt_rat
    bus.alloc_budget -= amt_rat
    record_spend(owner, amt_rat, "BUSINESS")
    
    data = Dict("bus_id" => bus_id, "amount" => amt_rat, "purpose" => purpose, "new_value" => get_member_coin_value())
    tx = Transaction("BUSINESS_SPEND", owner, "EXO", data)
    add_transaction(tx, owner)
    
    println("✅ Business spend: $amt_rat for $purpose (exact)")
end

# Pledges (Enhanced with Recurring for Business)
# ============================================================================
function create_pledge(name::String, target::Float64, creator::String, net_id::String, purpose::String, is_business::Bool, recurring::Bool=false, monthly::Float64=0.0)
    if !haskey(BLOCKCHAIN.member_coins, creator) || !haskey(BLOCKCHAIN.networks, net_id)
        error("Requirements not met")
    end
    if recurring && !is_business
        error("Recurring only for business pledges")
    end
    id = string(uuid4())
    pledge = Pledge(id, name, creator, net_id, target, purpose, is_business, recurring, monthly)
    BLOCKCHAIN.pledges[id] = pledge
    
    data = Dict("id" => id, "name" => name, "target" => pledge.target, "creator" => creator, "net_id" => net_id, "business" => is_business, "recurring" => recurring, "monthly" => pledge.monthly_amount)
    tx = Transaction("CREATE_PLEDGE", creator, id, data)
    add_transaction(tx, creator)
    
    println("✅ Pledge $name created ($(is_business ? "Business" : "Member"), recurring: $recurring)")
    return id
end

function support_pledge(pledge_id::String, amount::Float64, supporter::String)
    pledge = BLOCKCHAIN.pledges[pledge_id]
    amt_rat = Rational{BigInt}(BigInt(trunc(amount * 100)), BigInt(100))
    validate_spend(supporter, amt_rat, "PLEDGE")
    pledge.current += amt_rat
    pledge.supporters[supporter] = get(pledge.supporters, supporter, 0//1) + amt_rat
    record_spend(supporter, amt_rat, "PLEDGE")
    if pledge.current >= pledge.target
        pledge.completed = true
    end
    # Simulate recurring (demo only; real would schedule)
    if pledge.recurring && !pledge.completed
        println("📅 Recurring: Would auto-add $(pledge.monthly_amount) next month if unmet")
    end
    
    data = Dict("pledge_id" => pledge_id, "amount" => amt_rat, "supporter" => supporter, "current" => pledge.current)
    tx = Transaction("SUPPORT_PLEDGE", supporter, pledge_id, data)
    add_transaction(tx, supporter)
    
    println("✅ Pledge supported: $amt_rat (exact)")
end

# Status
# ============================================================================
function print_status()
    println("\n=== aequchain STATUS ===")
    println("Stablecoins: $(BLOCKCHAIN.treasury.stable_coins)")
    println("Value: $(get_treasury_value()) $(BLOCKCHAIN.treasury.peg_currency)")
    println("Members: $(get_total_members())")
    println("Value/Member: $(get_member_coin_value()) (exact)")
    println("Avg Contrib: $(BLOCKCHAIN.avg_contrib_rate)")
    println("Networks: $(length(BLOCKCHAIN.networks))")
    println("Businesses: $(length(BLOCKCHAIN.businesses))")
    println("Pledges: $(length(BLOCKCHAIN.pledges))")
    println("Blockchain: $(length(BLOCKCHAIN.blockchain))")
end

# Demo (With New Features)
# ============================================================================
function run_demo()
    init_treasury(100.0, "USD", 1.0, "founder")
    join_member("alice", 100.0)
    join_member("bob", 100.0)
    transfer("founder", "alice", 50.0)
    
    usd_net = create_network("USD_Net", "USD", 1.0, "founder")
    zar_net = create_network("ZAR_Net", "ZAR", 17.35, "alice")
    join_network("alice", usd_net)
    join_network("founder", zar_net)
    join_network("bob", usd_net)
    join_network("bob", zar_net)
    
    bus_id = create_business("EquiTech", "founder", usd_net)
    set_contrib_rate(bus_id, 0.03, "founder")
    
    # Member pledge (personal, e.g., holiday/immigration)
    member_pledge = create_pledge("HolidayFund", 1000.0, "alice", zar_net, "Overseas travel & immigration", false)
    support_pledge(member_pledge, 50.0, "bob")
    
    # Business pledge (funding, with recurring)
    bus_pledge = create_pledge("StartupBoost", 2000.0, "founder", usd_net, "Additional funding", true, true, 100.0)
    support_pledge(bus_pledge, 60.0, "alice")
    
    print_status()
    println("✅ Demo: Exact equality preserved; pledges enhanced")
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_demo()
end
