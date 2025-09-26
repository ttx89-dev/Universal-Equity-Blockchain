using SHA
using Dates
using Random
using UUIDs
using Printf

"""aequchain.jl

aequchain — Universal Equidistributed Blockchain (aequchain)

Summary
- Implementation of a demonstration Universal Equidistributed Blockchain (UEB) with exact monetary
  precision using Rational{BigInt}.
- Supports global member coins, networks, businesses, pledges (including recurring business pledges),
  a small immutable transaction/block structure, and a full interactive CLI.

Purpose
- Provide a reference/demo implementation focused on exact equality distribution semantics,
  safety checks (30-day spend limits), and multi-network business/pledge flows.
- Full interactive CLI for demonstrating all system functionality.

Quick usage
- julia --project -e 'include("aequchain.jl"); aequchain.run_minimal_cli()'
- Or: julia aequchain.jl cli

Notes & Caveats
- DEMO_MODE = true: no persistence, simplified recurring behavior, and supervisory checks.
- Monetary values are represented as Rational{BigInt} with cent precision.

License & Attribution
- Add appropriate license and attribution in the repository root as needed.

"""
# ============================================================================
# UNIVERSAL EQUIDISTRIBUTED BLOCKCHAIN (aequchain) - Exact Precision
# Merges UEB/EDS: Global equality, multi-network, safety; uses Rational for exact math
# ============================================================================
const DEMO_MODE = true  # Safe for testing; no persistence

# ANSI Color/Style Codes
const RESET = "\033[0m"
const BOLD = "\033[1m"
const ITALIC = "\033[3m"
# Use truecolor for the requested header hex (updated to #5a1344)
const WELCOME_HEX = "\033[38;2;90;19;68m"  # rgb(90,19,68) == #5a1344
const WHITE = "\033[37m"
# Accent and body colors for consistent yet legible palette
const ACCENT = BOLD * WELCOME_HEX
const BODY = WHITE
const CYAN = BODY
const GREY = "\033[38;2;155;155;155m"  # truecolor #9b9b9b
const GREEN = "\033[32m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const PROMPT_TEXT = "aequchain > "
const FEEDBACK_MESSAGE = Ref{String}("")

# Precision-safe conversion functions
"""Convert Float64 to Rational{BigInt} with exact decimal representation"""
function decimal_to_rational(x::Float64, decimals::Int=4)::Rational{BigInt}
    # Convert to string to avoid Float64 precision issues
    str_val = string(round(x, digits=decimals))
    
    if occursin('.', str_val)
        parts = split(str_val, '.')
        integer_part = parts[1]
        fractional_part = rpad(parts[2], decimals, '0')[1:decimals]
        numerator = parse(BigInt, integer_part * fractional_part)
        denominator = BigInt(10)^decimals
    else
        numerator = parse(BigInt, str_val)
        denominator = BigInt(1)
    end
    
    return numerator // denominator
end

"""Backward-compatible conversion for monetary amounts (2 decimals)"""
function money_to_rational(amount::Float64)::Rational{BigInt}
    return decimal_to_rational(amount, 2)
end

"""High-precision conversion for rates (4 decimals)"""
function rate_to_rational(rate::Float64)::Rational{BigInt}
    return decimal_to_rational(rate, 4)
end

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
    
    Network(id::String, name::String, denom::String, rate::Float64) = new(id, name, denom, rate_to_rational(rate), Set{String}(), Dict{String, String}(), now())
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
    alloc_budget::Rational{BigInt}  # Remaining spending allocation
    allocation_cap::Rational{BigInt}  # Maximum allocation allowed this cycle
    created_at::DateTime
    
    Business(id::String, name::String, owner::String, network::String) = new(id, name, owner, network, 0//1, Set{String}(), 0//1, 0//1, now())
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
        new(id, name, creator, network, money_to_rational(target), 0//1, Dict{String, Rational{BigInt}}(), purpose, is_business, recurring && is_business, money_to_rational(monthly), false, now())
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
const MEMBER_COIN_VALUE_CACHE = Ref{Rational{BigInt}}(0//1)
const MEMBER_COUNT_CACHE = Ref{Int}(0)
const CURRENT_USER = Ref{String}("")  # Track current logged-in user

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
    if MEMBER_COIN_VALUE_CACHE[] == 0//1 || length(BLOCKCHAIN.member_coins) != MEMBER_COUNT_CACHE[]
        MEMBER_COUNT_CACHE[] = length(BLOCKCHAIN.member_coins)
        MEMBER_COIN_VALUE_CACHE[] = BLOCKCHAIN.treasury.stable_coins // max(1, length(BLOCKCHAIN.member_coins))
    end
    return MEMBER_COIN_VALUE_CACHE[]
end

function get_treasury_value()
    return BLOCKCHAIN.treasury.stable_coins  # Already in peg currency!
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
function validate_member_doesnt_exist(id::String)
    if haskey(BLOCKCHAIN.member_coins, id)
        error("Member $id already exists")
    end
end

function validate_non_negative_deposit(deposit::Float64)
    if deposit < 0
        error("Deposit cannot be negative")
    end
end

function init_treasury(initial_funds::Float64, currency::String, peg_rate::Float64, founder::String)
    if !isempty(BLOCKCHAIN.member_coins)
        error("Treasury already initialized")
    end
    funds_rat = money_to_rational(initial_funds)
    rate_rat = rate_to_rational(peg_rate)
    BLOCKCHAIN.treasury.stable_coins = funds_rat // rate_rat
    BLOCKCHAIN.treasury.peg_currency = currency
    BLOCKCHAIN.treasury.peg_rate = rate_rat
    join_member(founder, initial_funds)
end

function join_member(id::String, deposit::Float64=0.0)
    validate_member_doesnt_exist(id)
    validate_non_negative_deposit(deposit)
    dep_rat = money_to_rational(deposit)
    stable_deposit = dep_rat // BLOCKCHAIN.treasury.peg_rate
    BLOCKCHAIN.treasury.stable_coins += stable_deposit
    BLOCKCHAIN.members[id] = Member(id)
    BLOCKCHAIN.member_coins[id] = MemberCoin(id)
    MEMBER_COUNT_CACHE[] = 0  # Invalidate cache
    
    new_share = get_member_coin_value()
    data = Dict(
        "member" => id, 
        "deposit" => dep_rat, 
        "voluntary_contribution" => dep_rat > 0,
        "total_members" => get_total_members(), 
        "new_equal_share" => new_share
    )
    tx = Transaction("JOIN_MEMBER", id, "TREASURY", data)
    add_transaction(tx, id)
    
    println("✅ $id joined society. Equal share: $new_share")
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
    MEMBER_COUNT_CACHE[] = 0  # Invalidate cache
    
    data = Dict("member" => id, "refund" => refund, "new_value" => get_member_coin_value())
    tx = Transaction("EXIT_MEMBER", id, "TREASURY", data)
    add_transaction(tx, first(keys(BLOCKCHAIN.member_coins)))
    
    println("✅ Member $id exited: refund $refund (exact)")
    return refund
end

# Withdrawals (External Spending while Preserving Equality)
# ============================================================================
function member_withdraw(member_id::String, amount::Float64, purpose::String)
    if !haskey(BLOCKCHAIN.members, member_id)
        error("Member not found")
    end
    if amount <= 0
        error("Withdrawal amount must be positive")
    end
    amt_rat = money_to_rational(amount)
    validate_spend(member_id, amt_rat, "WITHDRAW")
    if amt_rat > BLOCKCHAIN.treasury.stable_coins
        error("Insufficient treasury funds")
    end
    BLOCKCHAIN.treasury.stable_coins -= amt_rat
    record_spend(member_id, amt_rat, "WITHDRAW")
    data = Dict(
        "member" => member_id,
        "amount" => amt_rat,
        "purpose" => purpose,
        "new_value" => get_member_coin_value()
    )
    tx = Transaction("MEMBER_WITHDRAW", member_id, "EXTERNAL", data)
    add_transaction(tx, member_id)
    println("✅ Member $member_id withdrew $amt_rat for $purpose (exact)")
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

function join_network(member_id::String, net_id::String; silent::Bool=false)
    if !haskey(BLOCKCHAIN.member_coins, member_id) || !haskey(BLOCKCHAIN.networks, net_id)
        error("Not found")
    end
    net = BLOCKCHAIN.networks[net_id]
    member = BLOCKCHAIN.members[member_id]
    push!(net.members, member_id)
    push!(member.networks, net_id)
    if !silent
        data = Dict{String, Any}("member" => member_id, "net_id" => net_id)
        tx = Transaction("JOIN_NETWORK", member_id, net_id, data)
        add_transaction(tx, member_id)
        println("✅ $member_id joined $net_id")
    end
end

function leave_network(member_id::String, net_id::String; silent::Bool=false)
    if !haskey(BLOCKCHAIN.member_coins, member_id) || !haskey(BLOCKCHAIN.networks, net_id)
        error("Not found")
    end
    member = BLOCKCHAIN.members[member_id]
    net = BLOCKCHAIN.networks[net_id]
    if !(member_id in net.members)
        error("Member $member_id is not part of network $(net.name)")
    end
    delete!(net.members, member_id)
    delete!(member.networks, net_id)
    if !silent
        data = Dict{String, Any}("member" => member_id, "net_id" => net_id)
        tx = Transaction("LEAVE_NETWORK", member_id, net_id, data)
        add_transaction(tx, member_id)
        println("✅ $member_id left $(net.name)")
    end
end

function transfer_network(member_id::String, from_net_id::String, to_net_id::String)
    if from_net_id == to_net_id
        error("Source and destination networks must differ")
    end
    if !haskey(BLOCKCHAIN.member_coins, member_id)
        error("Member not found")
    end
    if !haskey(BLOCKCHAIN.networks, from_net_id) || !haskey(BLOCKCHAIN.networks, to_net_id)
        error("Network not found")
    end
    member = BLOCKCHAIN.members[member_id]
    from_net = BLOCKCHAIN.networks[from_net_id]
    to_net = BLOCKCHAIN.networks[to_net_id]
    if !(from_net_id in member.networks)
        error("Member $member_id is not part of the source network")
    end
    if to_net_id in member.networks
        error("Member $member_id already belongs to the destination network")
    end
    leave_network(member_id, from_net_id; silent=true)
    join_network(member_id, to_net_id; silent=true)
    data = Dict{String, Any}(
        "member" => member_id,
        "from" => from_net_id,
        "to" => to_net_id,
        "from_name" => from_net.name,
        "to_name" => to_net.name
    )
    tx = Transaction("TRANSFER_NETWORK", member_id, to_net_id, data)
    add_transaction(tx, member_id)
    println("✅ $member_id transferred from $(from_net.name) to $(to_net.name)")
end

function resolve_network_id(identifier::String)
    if haskey(BLOCKCHAIN.networks, identifier)
        return identifier
    end
    lowered = lowercase(identifier)
    for (id, net) in BLOCKCHAIN.networks
        if lowercase(net.name) == lowered
            return id
        end
    end
    return nothing
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

function refresh_business_allocation!(bus::Business; reset::Bool=false)
    target = bus.contrib_rate * get_member_coin_value() * length(bus.employees)
    if reset
        additional = max(0//1, target - bus.allocation_cap)
        bus.alloc_budget += additional
    end
    bus.allocation_cap = target
    if bus.alloc_budget > bus.allocation_cap
        bus.alloc_budget = bus.allocation_cap
    elseif bus.alloc_budget < 0//1
        bus.alloc_budget = 0//1
    end
end

function set_contrib_rate(bus_id::String, rate::Float64, owner::String)
    bus = BLOCKCHAIN.businesses[bus_id]
    rate_rat = rate_to_rational(rate)
    if bus.owner != owner || rate_rat < 0//1 || rate_rat > 5//100
        error("Invalid")
    end
    bus.contrib_rate = rate_rat
    refresh_business_allocation!(bus; reset=true)
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

function hire_member(bus_id::String, member_id::String, owner::String)
    if !haskey(BLOCKCHAIN.businesses, bus_id) || !haskey(BLOCKCHAIN.members, member_id)
        error("Business or member not found")
    end
    bus = BLOCKCHAIN.businesses[bus_id]
    if bus.owner != owner
        error("Only the business owner can hire members")
    end
    if member_id in bus.employees
        error("$member_id is already employed by $(bus.name)")
    end
    push!(bus.employees, member_id)
    push!(BLOCKCHAIN.members[member_id].businesses_employed, bus_id)
    refresh_business_allocation!(bus; reset=true)
    
    data = Dict(
        "business" => bus_id,
        "member" => member_id,
        "owner" => owner,
        "employees" => length(bus.employees)
    )
    tx = Transaction("HIRE_MEMBER", owner, bus_id, data)
    add_transaction(tx, owner)
    
    println("✅ $member_id hired into $(bus.name)")
end

function business_withdraw(bus_id::String, amount::Float64, purpose::String, actor::String)
    if !haskey(BLOCKCHAIN.businesses, bus_id)
        error("Business not found")
    end
    bus = BLOCKCHAIN.businesses[bus_id]
    if bus.owner != actor
        error("Only the business owner can withdraw from the allocation")
    end
    if amount <= 0
        error("Withdrawal amount must be positive")
    end
    amt_rat = money_to_rational(amount)
    refresh_business_allocation!(bus)
    if amt_rat > bus.alloc_budget
        error("Insufficient business allocation")
    end
    if amt_rat > BLOCKCHAIN.treasury.stable_coins
        error("Insufficient treasury funds")
    end
    validate_spend(actor, amt_rat, "BUSINESS_WITHDRAW")
    BLOCKCHAIN.treasury.stable_coins -= amt_rat
    bus.alloc_budget -= amt_rat
    if bus.alloc_budget < 0//1
        bus.alloc_budget = 0//1
    end
    record_spend(actor, amt_rat, "BUSINESS_WITHDRAW")
    
    data = Dict(
        "business" => bus_id,
        "amount" => amt_rat,
        "purpose" => purpose,
        "remaining_allocation" => bus.alloc_budget,
        "new_value" => get_member_coin_value()
    )
    tx = Transaction("BUSINESS_WITHDRAW", actor, "EXTERNAL", data)
    add_transaction(tx, actor)
    
    println("✅ Business $(bus.name) withdrew $amt_rat for $purpose (exact)")
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
    amt_rat = money_to_rational(amount)
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

# Simplified Recurring Pledge Processing (Demo)
function process_recurring_pledges()
    current_time = now()
    for pledge in values(BLOCKCHAIN.pledges)
        if pledge.recurring && !pledge.completed
            # Convert time difference to milliseconds and then to months
            time_diff_ms = current_time - pledge.created_at
            days_passed = time_diff_ms.value / (1000 * 60 * 60 * 24)  # Convert to days
            months_passed = round(Int, days_passed / 30)  # Approximate months
            if months_passed > 0
                auto_amount = months_passed * pledge.monthly_amount
                if can_business_afford(pledge.creator, auto_amount)
                    support_pledge(pledge.id, Float64(auto_amount), pledge.creator)
                    println("📅 Auto-added recurring pledge: $auto_amount for $(pledge.name)")
                else
                    println("⚠️ Insufficient funds for recurring pledge: $(pledge.name)")
                end
            end
        end
    end
end

# Helper function to check if a business can afford the recurring amount
function can_business_afford(owner::String, amount::Rational{BigInt})
    business = first(values(BLOCKCHAIN.businesses))  # Simplification for demo
    return business.alloc_budget >= amount
end

# Status
# ============================================================================
function print_status()
    println("\n$(ACCENT)=== aequchain STATUS ===$(RESET)")
    println("$(ACCENT)Stablecoins:$(RESET) $(BODY)$(BLOCKCHAIN.treasury.stable_coins)$(RESET)")
    println("$(ACCENT)Value:$(RESET) $(BODY)$(get_treasury_value()) $(BLOCKCHAIN.treasury.peg_currency)$(RESET)")
    println("$(ACCENT)Members:$(RESET) $(BODY)$(get_total_members())$(RESET)")
    println("$(ACCENT)Value/Member:$(RESET) $(BODY)$(get_member_coin_value())$(RESET) $(GREY)(exact)$(RESET)")
    println("$(ACCENT)Avg Contrib:$(RESET) $(BODY)$(BLOCKCHAIN.avg_contrib_rate)$(RESET)")
    println("$(ACCENT)Networks:$(RESET) $(BODY)$(length(BLOCKCHAIN.networks))$(RESET)")
    println("$(ACCENT)Businesses:$(RESET) $(BODY)$(length(BLOCKCHAIN.businesses))$(RESET)")
    println("$(ACCENT)Pledges:$(RESET) $(BODY)$(length(BLOCKCHAIN.pledges))$(RESET)")
    println("$(ACCENT)Blockchain:$(RESET) $(BODY)$(length(BLOCKCHAIN.blockchain))$(RESET)")
end

# Enhanced CLI Interface
# ============================================================================
const CLI_HEADER_TITLE = "WELCOME"
const CLI_HEADER_SUBTITLE = "we are glad that you are here"

center_text(text::AbstractString, width::Int) = begin
    padding = max(0, (width - length(text)) ÷ 2)
    string(repeat(" ", padding), text)
end

function clear_screen()
    print("\033[2J\033[H")
    flush(stdout)
end

function get_terminal_size()
    try
        rows, cols = displaysize(stdout)
        return (cols, rows)
    catch
        return (80, 24)
    end
end

function render_header(title::String="")
    cols, _ = get_terminal_size()
    # Print header text at top-left using the requested hex color with single space
    println("\033[1;1H\033[2K $(BOLD)$(WELCOME_HEX)$(CLI_HEADER_TITLE)$(RESET)")
    if !isempty(strip(FEEDBACK_MESSAGE[]))
        message = length(FEEDBACK_MESSAGE[]) > cols ? FEEDBACK_MESSAGE[][end-cols+1:end] : FEEDBACK_MESSAGE[]
        start_col = max(1, cols - length(message) + 1)
        print("\033[1;$(start_col)H$(WELCOME_HEX)$(message)$(RESET)")
    end
    println("\033[2;1H\033[2K $(ITALIC)$(WELCOME_HEX)$(CLI_HEADER_SUBTITLE)$(RESET)")
    
    if !isempty(title)
        # Print section titles left-aligned with grey color and capitals, starting from line 4
        title_line = 4
        # Left-aligned title with grey color and capitals
        println("\033[$(title_line);1H$(GREY)$(uppercase(title))$(RESET)")
        println("\033[$(title_line + 1);1H$(repeat('─', 50))")
    end
end

function pause_for_enter(; print_message::Bool=true, message_line::Union{Nothing, Int}=nothing)
    if print_message
        if isnothing(message_line)
            println()
            print("Press Enter to continue...")
        else
            print("\033[$(message_line);1H\033[2KPress Enter to continue...")
        end
    end
    try
        readline()
    catch e
        if !(e isa EOFError)
            rethrow()
        end
    end
end

function display_welcome(first_run::Bool=true)
    width, height = get_terminal_size()
    clear_screen()
    render_header()
    
    # Position the prompt area roughly in the middle of the screen
            prompt_line = max(5, height ÷ 2)
    
    # Move cursor to the prompt line
    print("\033[$(prompt_line);1H")

    # Print the prompt as bold white only using PROMPT_TEXT
    print("$(BOLD)$(WHITE)$(PROMPT_TEXT)$(RESET)")

    # Move to the line below the prompt and display hint in the welcome color (italic).
    print("\033[$(prompt_line + 1);1H")
    if first_run
        print("$(WELCOME_HEX)$(ITALIC)type 'help' for options | 'demo' for automation$(RESET)")
    else
        print("$(WELCOME_HEX)$(ITALIC)type 'help' for options | 'example' for the walkthrough$(RESET)")
    end

    # After the hint, set user input color to grey and position cursor after the prompt
    print("$(GREY)")
    prompt_length = length(PROMPT_TEXT)
    # Position cursor on the prompt line just after the visible prompt text
    print("\033[$(prompt_line);$(prompt_length + 1)H") # Position after prompt

    # Draw the footer immediately so it remains fixed on the bottom line
    render_footer()
end

set_feedback(msg::AbstractString) = (FEEDBACK_MESSAGE[] = String(msg))
clear_feedback() = (FEEDBACK_MESSAGE[] = "")

function help_content_paginated()
    _, rows = get_terminal_size()
    # Reserve space for header (6 lines), "Press Enter..." (1), footer (1), some padding
    available_rows = max(8, rows - 10)
    
    # Define help sections as separate content blocks
    sections = [
        () -> begin
            println("$(ACCENT)MEMBERSHIP$(RESET)")
            println("  $(ACCENT)login <id>$(RESET)                    $(BODY)- login as member$(RESET)")
            println("  $(ACCENT)join <id> [deposit]$(RESET)           $(BODY)- add new member$(RESET)")
            println("  $(ACCENT)balance [id]$(RESET)                  $(BODY)- check member balance$(RESET)")
            println("  $(ACCENT)withdraw <amount> [purpose]$(RESET)   $(BODY)- member external withdrawal$(RESET)")
            println("  $(ACCENT)logout$(RESET)                        $(BODY)- leave current session$(RESET)")
            println("  $(ACCENT)exit_member <id>$(RESET)              $(BODY)- remove member$(RESET)")
            println()
            println("$(ACCENT)NETWORKS$(RESET)")
            println("  $(ACCENT)create_net <name> <denom> <rate>$(RESET) $(BODY)- create network$(RESET)")
            println("  $(ACCENT)join_net <net_id|name>$(RESET)        $(BODY)- join network$(RESET)")
            println("  $(ACCENT)transfer_net <from> <to>$(RESET)      $(BODY)- move membership between networks$(RESET)")
            println("  $(ACCENT)networks$(RESET)                      $(BODY)- list networks$(RESET)")
        end,
        () -> begin
            println("$(ACCENT)BUSINESSES$(RESET)")
            println("  $(ACCENT)create_bus <name> <net_id>$(RESET)    $(BODY)- create business$(RESET)")
            println("  $(ACCENT)set_ec <bus_id> <rate>$(RESET)        $(BODY)- set enterprise contribution$(RESET)")
            println("  $(ACCENT)hire <bus_id> <member_id>$(RESET)     $(BODY)- add member to business$(RESET)")
            println("  $(ACCENT)bus_withdraw <bus_id> <amount> <purpose>$(RESET) $(BODY)- business external payment$(RESET)")
            println("  $(ACCENT)businesses$(RESET)                    $(BODY)- list businesses$(RESET)")
            println()
            println("$(ACCENT)PLEDGES$(RESET)")
            println("  $(ACCENT)create_pledge <name> <target> <net_id> <purpose> <type>$(RESET)")
            println("                                       $(BODY)type: member | business$(RESET)")
            println("                                       $(BODY)business pledges: add 'recurring <monthly_amount>' for monthly cycles$(RESET)")
            println("  $(ACCENT)support <pledge_id> <amount>$(RESET)  $(BODY)- support pledge$(RESET)")
            println("  $(ACCENT)pledges$(RESET)                       $(BODY)- list pledges$(RESET)")
        end,
        () -> begin
            println("$(ACCENT)SYSTEM$(RESET)")
            println("  $(ACCENT)status$(RESET)                        $(BODY)- system status$(RESET)")
            println()
            println("$(ACCENT)NAVIGATION$(RESET)")
            println("  $(ACCENT)demo$(RESET)                          $(BODY)- run full demonstration$(RESET)")
            println("  $(ACCENT)example$(RESET)                       $(BODY)- step-by-step realistic walkthrough$(RESET)")
            println("  $(ACCENT)reset$(RESET)                         $(BODY)- clear all data$(RESET)")
            println("  $(ACCENT)help$(RESET)                          $(BODY)- show this help$(RESET)")
            println("  $(ACCENT)exit$(RESET)                          $(BODY)- quit system$(RESET)")
        end,
        () -> begin
            println("$(ACCENT)SECURITY AND PRIVACY$(RESET)")
            println("  $(GREY)- no files created on your computer$(RESET)")
            println("  $(GREY)- all information resides in memory only$(RESET)")
            println("  $(GREY)- exit or reset leaves nothing behind$(RESET)")
        end
    ]
    
    # Show each section with pagination
    for (i, section_func) in enumerate(sections)
        clear_screen()
        render_header("AVAILABLE COMMANDS")
        
        section_func()
        
        # Show pagination prompt
        _, rows = get_terminal_size()
        message_line = max(4, rows - 2)
        
        if i < length(sections)
            print("\033[$(message_line);1H\033[2KPress Enter to continue...")
        else
            print("\033[$(message_line);1H\033[2KPress Enter to return to main menu...")
        end
        
        render_footer()
        pause_for_enter(print_message=false)
    end
end

function help_content()
    println("$(ACCENT)MEMBERSHIP$(RESET)")
    println("  $(ACCENT)login <id>$(RESET)                    $(BODY)- login as member$(RESET)")
    println("  $(ACCENT)join <id> [deposit]$(RESET)           $(BODY)- add new member$(RESET)")
    println("  $(ACCENT)balance [id]$(RESET)                  $(BODY)- check member balance$(RESET)")
    println("  $(ACCENT)withdraw <amount> [purpose]$(RESET)   $(BODY)- member external withdrawal$(RESET)")
    println("  $(ACCENT)logout$(RESET)                        $(BODY)- leave current session$(RESET)")
    println("  $(ACCENT)exit_member <id>$(RESET)              $(BODY)- remove member$(RESET)")
    
    println("\n$(ACCENT)NETWORKS$(RESET)")
    println("  $(ACCENT)create_net <name> <denom> <rate>$(RESET) $(BODY)- create network$(RESET)")
    println("  $(ACCENT)join_net <net_id|name>$(RESET)        $(BODY)- join network$(RESET)")
    println("  $(ACCENT)transfer_net <from> <to>$(RESET)      $(BODY)- move membership between networks$(RESET)")
    println("  $(ACCENT)networks$(RESET)                      $(BODY)- list networks$(RESET)")
    
    println("\n$(ACCENT)BUSINESSES$(RESET)")
    println("  $(ACCENT)create_bus <name> <net_id>$(RESET)    $(BODY)- create business$(RESET)")
    println("  $(ACCENT)set_ec <bus_id> <rate>$(RESET)        $(BODY)- set enterprise contribution$(RESET)")
    println("  $(ACCENT)hire <bus_id> <member_id>$(RESET)     $(BODY)- add member to business$(RESET)")
    println("  $(ACCENT)bus_withdraw <bus_id> <amount> <purpose>$(RESET) $(BODY)- business external payment$(RESET)")
    println("  $(ACCENT)businesses$(RESET)                    $(BODY)- list businesses$(RESET)")
    
    println("\n$(ACCENT)PLEDGES$(RESET)")
    println("  $(ACCENT)create_pledge <name> <target> <net_id> <purpose> <type>$(RESET)")
    println("                                       $(BODY)type: member | business$(RESET)")
    println("                                       $(BODY)business pledges: add 'recurring <monthly_amount>' for monthly cycles$(RESET)")
    println("  $(ACCENT)support <pledge_id> <amount>$(RESET)  $(BODY)- support pledge$(RESET)")
    println("  $(ACCENT)pledges$(RESET)                       $(BODY)- list pledges$(RESET)")
    
    println("\n$(ACCENT)SYSTEM$(RESET)")
    println("  $(ACCENT)status$(RESET)                        $(BODY)- system status$(RESET)")
    
    println("\n$(ACCENT)NAVIGATION$(RESET)")
    println("  $(ACCENT)demo$(RESET)                          $(BODY)- run full demonstration$(RESET)")
    println("  $(ACCENT)example$(RESET)                       $(BODY)- guided walkthrough of every command$(RESET)")
    println("  $(ACCENT)reset$(RESET)                         $(BODY)- clear all data$(RESET)")
    println("  $(ACCENT)help$(RESET)                          $(BODY)- show this help$(RESET)")
    println("  $(ACCENT)exit$(RESET)                          $(BODY)- quit system$(RESET)")
    
    println("\n$(ACCENT)SECURITY AND PRIVACY$(RESET)")
    println("  $(GREY)- no files created on your computer$(RESET)")
    println("  $(GREY)- all information resides in memory only$(RESET)")
    println("  $(GREY)- exit or reset leaves nothing behind$(RESET)")
end

show_help() = help_content_paginated()

function example_walkthrough_sections()
    return [
        [
            "$(ACCENT)Realistic Walkthrough — Every Command$(RESET)",
            "$(GREY)Tip: jot down network, business, and pledge IDs as they are printed so you can reuse them in later steps.$(RESET)",
            "",
            "$(ACCENT)Foundation$(RESET)",
            " 1. Start fresh: $(ACCENT)reset$(RESET)",
            " 2. Mint the founder with capital: $(ACCENT)join founder 150$(RESET)",
            " 3. Hold the wheel: $(ACCENT)login founder$(RESET)",
            " 4. Launch a USD network: $(ACCENT)create_net USD_Net USD 1.0$(RESET)",
            " 5. Launch a ZAR network: $(ACCENT)create_net ZAR_Net ZAR 17.35$(RESET)",
            " 6. Step back for new members: $(ACCENT)logout$(RESET)",
        ],
        [
            "$(ACCENT)Members Join$(RESET)",
            " 7. Welcome Alice with savings: $(ACCENT)join alice 100$(RESET)",
            " 8. $(ACCENT)login alice$(RESET) → $(ACCENT)join_net USD_Net$(RESET)   $(GREY)(Alice joins the USD network.)$(RESET)",
            " 9. $(ACCENT)logout$(RESET)",
            "10. Invite Bob: $(ACCENT)join bob 25$(RESET) → $(ACCENT)login bob$(RESET) → $(ACCENT)join_net USD_Net$(RESET)",
            "11. $(ACCENT)logout$(RESET)",
            "12. Add Carla: $(ACCENT)join carla 75$(RESET) → $(ACCENT)login carla$(RESET) → $(ACCENT)join_net USD_Net$(RESET)",
            "13. Carla covers essentials: $(ACCENT)withdraw 20 essentials$(RESET)",
            "14. $(ACCENT)logout$(RESET)",
            "15. Invite Dave: $(ACCENT)join dave 10$(RESET) → $(ACCENT)login dave$(RESET) → $(ACCENT)join_net ZAR_Net$(RESET)",
            "16. $(ACCENT)logout$(RESET)",
        ],
        [
            "$(ACCENT)Build Businesses$(RESET)",
            "17. Founder seeds a USD venture: $(ACCENT)login founder$(RESET) → $(ACCENT)create_bus EquiTech USD_Net$(RESET)",
            "    • Note the printed business ID (call it EQ).",
            "18. Encourage sharing: $(ACCENT)set_ec EQ 0.03$(RESET)",
            "19. Hire locally: $(ACCENT)hire EQ alice$(RESET) → $(ACCENT)hire EQ carla$(RESET)",
            "20. Fund early prototypes: $(ACCENT)bus_withdraw EQ 2.0 prototype-materials$(RESET)",
            "21. $(ACCENT)logout$(RESET)",
            "",
            "22. Alice launches a cross-border co-op: $(ACCENT)login alice$(RESET) → $(ACCENT)create_bus UbuntuWorks ZAR_Net$(RESET)",
            "    • Capture this business ID (call it UB).",
            "23. Set community contribution: $(ACCENT)set_ec UB 0.025$(RESET)",
            "24. Hire Bob for remote collaboration: $(ACCENT)hire UB bob$(RESET)",
            "25. Bring Dave aboard in his home network: $(ACCENT)hire UB dave$(RESET)",
            "26. Fund a community rollout: $(ACCENT)bus_withdraw UB 1.5 community-rollout$(RESET)",
            "27. $(ACCENT)logout$(RESET)",
        ],
        [
            "$(ACCENT)Cross-Network Mobility$(RESET)",
            "28. Bob relocates for work: $(ACCENT)login bob$(RESET) → $(ACCENT)transfer_net USD_Net ZAR_Net$(RESET) → $(ACCENT)logout$(RESET)",
            "",
            "$(ACCENT)Pledges & Support$(RESET)",
            "29. Alice raises travel support: $(ACCENT)login alice$(RESET) → $(ACCENT)create_pledge HolidayFund 1000 ZAR_Net travel member$(RESET)",
            "    • Save this pledge ID (call it HF).",
            "30. $(ACCENT)logout$(RESET)",
            "31. Carla invests in the dream: $(ACCENT)login carla$(RESET) → $(ACCENT)support HF 40$(RESET) → $(ACCENT)logout$(RESET)",
            "32. Dave pledges support funds for Carla's holiday: $(ACCENT)login dave$(RESET) → $(ACCENT)support HF 35$(RESET) → $(ACCENT)logout$(RESET)",
        ],
        [
            "$(ACCENT)Growth Campaign$(RESET)",
            "33. Founder launches a growth pledge: $(ACCENT)login founder$(RESET) → $(ACCENT)create_pledge StartupBoost 2000 USD_Net expansion business recurring 120$(RESET)",
            "    • Keep this pledge ID (call it SB).",
            "34. Founder seeds it: $(ACCENT)support SB 60$(RESET) → $(ACCENT)logout$(RESET)",
            "35. Alice doubles down: $(ACCENT)login alice$(RESET) → $(ACCENT)support SB 55$(RESET) → $(ACCENT)logout$(RESET)",
            "",
            "$(ACCENT)Review & Close$(RESET)",
            "36. Inspect the system: $(ACCENT)status$(RESET)",
            "37. Explore networks: $(ACCENT)networks$(RESET)",
            "38. Review businesses: $(ACCENT)businesses$(RESET)",
            "39. Check pledges: $(ACCENT)pledges$(RESET)",
            "40. Inspect a balance (e.g., Alice): $(ACCENT)balance alice$(RESET)",
            "41. When finished, either $(ACCENT)reset$(RESET) for another tour or $(ACCENT)exit$(RESET) to leave the CLI.",
        ]
    ]
end

function example_content_paginated()
    _, rows = get_terminal_size()
    available_rows = max(8, rows - 10)
    sections = example_walkthrough_sections()
    for (idx, lines) in enumerate(sections)
        clear_screen()
        render_header("EXAMPLE WALKTHROUGH")
        printed = 0
        for line in lines
            println(line)
            printed += 1
            if printed >= available_rows && line != lines[end]
                println()
                println("$(GREY)[Section truncated to fit screen height]$(RESET)")
                break
            end
        end
        _, rows = get_terminal_size()
        message_line = max(4, rows - 2)
        if idx < length(sections)
            print("\033[$(message_line);1H\033[2KPress Enter to continue...")
        else
            print("\033[$(message_line);1H\033[2KPress Enter to return to main menu...")
        end
        render_footer()
        pause_for_enter(print_message=false)
    end
end

function show_networks()
    if isempty(BLOCKCHAIN.networks)
        println("No networks created yet.")
        return
    end

    for net in values(BLOCKCHAIN.networks)
        denom_value = @sprintf("%.4f", Float64(net.denom_rate))
        println("$(CYAN)Name:$(RESET) $(net.name) ($(net.id))")
        println("  $(CYAN)Denomination:$(RESET) $(net.denomination) (Rate: 1 stablecoin = $denom_value)")
        println("  $(CYAN)Members:$(RESET) $(length(net.members))")
        println("  $(CYAN)Businesses:$(RESET) $(length(net.businesses))")
        if length(net.members) > 0
            println("  $(CYAN)Member IDs:$(RESET) $(join(net.members, ", "))")
        end
        println()
    end
end

function show_businesses()
    if isempty(BLOCKCHAIN.businesses)
        println("No businesses created yet.")
        return
    end

    for bus in values(BLOCKCHAIN.businesses)
        net = BLOCKCHAIN.networks[bus.network_id]
        rate_display = @sprintf("%.2f%%", Float64(bus.contrib_rate * 100))
        println("$(CYAN)Name:$(RESET) $(bus.name) ($(bus.id))")
        println("  $(CYAN)Owner:$(RESET) $(bus.owner)")
        println("  $(CYAN)Network:$(RESET) $(net.name)")
        println("  $(CYAN)Contribution Rate:$(RESET) $(rate_display)")
        println("  $(CYAN)Employees:$(RESET) $(length(bus.employees))")
        if !isempty(bus.employees)
            println("    $(CYAN)Members:$(RESET) $(join(collect(bus.employees), ", "))")
        end
        println("  $(CYAN)Budget Remaining:$(RESET) $(bus.alloc_budget)")
        println("  $(CYAN)Budget Cap:$(RESET) $(bus.allocation_cap)")
        println()
    end
end

function show_pledges()
    if isempty(BLOCKCHAIN.pledges)
        println("No pledges created yet.")
        return
    end

    for pledge in values(BLOCKCHAIN.pledges)
        type = pledge.is_business ? "Business" : "Member"
        status = pledge.completed ? "✅ Completed" : "🔄 Active"
        recurring = pledge.recurring ? " (recurring)" : ""
        progress = Float64(pledge.current) / Float64(pledge.target) * 100
        progress_bar = "[" * repeat("█", round(Int, progress/10)) * repeat("░", 10-round(Int, progress/10)) * "]"
        
        println("$(CYAN)Name:$(RESET) $(pledge.name) ($(pledge.id))")
        println("  $(CYAN)Type:$(RESET) $(type)$(recurring) - $(status)")
        println("  $(CYAN)Target:$(RESET) $(pledge.target) | $(CYAN)Current:$(RESET) $(pledge.current)")
        println("  $(CYAN)Progress:$(RESET) $(@sprintf("%.1f", progress))% $progress_bar")
        println("  $(CYAN)Purpose:$(RESET) $(pledge.purpose)")
        println("  $(CYAN)Supporters:$(RESET) $(length(pledge.supporters))")
        if length(pledge.supporters) > 0
            println("  $(CYAN)Supporter IDs:$(RESET) $(join(keys(pledge.supporters), ", "))")
        end
        println()
    end
end

function show_member_balance(member_id::String="")
    if isempty(member_id)
        if isempty(CURRENT_USER[])
            println("Please login first or specify member ID")
            return
        end
        member_id = CURRENT_USER[]
    end
    
    if !haskey(BLOCKCHAIN.members, member_id)
        println("Member $member_id not found")
        return
    end
    
    member = BLOCKCHAIN.members[member_id]
    clean_spend_history(member_id)
    allowance = get_spend_allowance(member_id)
    share_value = get_member_coin_value()
    
    println("$(CYAN)Equal Share Value:$(RESET) $share_value")
    println("$(CYAN)30-Day Allowance:$(RESET) $allowance")
    println("$(CYAN)Networks Joined:$(RESET) $(length(member.networks))")
    println("$(CYAN)Businesses Owned:$(RESET) $(length(member.businesses_owned))")
    println("$(CYAN)Businesses Employed:$(RESET) $(length(member.businesses_employed))")
    
    if !isempty(member.networks)
        println("\n$(CYAN)Network Values:$(RESET)")
        for net_id in member.networks
            net = BLOCKCHAIN.networks[net_id]
            denom_value = share_value * net.denom_rate
            println("  $(net.name): $denom_value $(net.denomination)")
        end
    end
    
    if !isempty(member.spend_history)
        println("\n$(CYAN)Recent Spending (30 days):$(RESET)")
        for (time, amount, typ) in member.spend_history[end-2:end]  # Last 3 transactions
            time_str = Dates.format(time, "yyyy-mm-dd HH:MM")
            println("  $time_str: $amount ($typ)")
        end
    end
end

function render_footer()
    # Place a small status at the bottom of the terminal: "/// guest" or user
    cols, rows = get_terminal_size()
    footer_text = isempty(CURRENT_USER[]) ? "/// guest" : "/// " * CURRENT_USER[]
    color = WELCOME_HEX  # Use same color as WELCOME for consistency
    # Move to bottom line, clear it, and print footer
    # Save cursor position, draw footer, then restore cursor so the input
    # cursor remains where the user was typing (after the prompt).
    print("\033[s")            # save cursor
    print("\033[$(rows);1H\033[2K")
    print("$(color)$(footer_text)$(RESET)")
    print("\033[u")            # restore cursor
    flush(stdout)
end

# Unified exit banner so edits are reflected regardless of how we exit
function print_exit_banner(msg::Union{Nothing,String}=nothing)
    # Default message (you can edit this single function to change banner text)
    default_msg = "        ...imagine the potential..."
    display_msg = msg === nothing ? default_msg : msg
    # Format: bold white 'aequchain' | grey 'closing' then italicized lightened-maroon message
    println("$(BOLD)$(WHITE)aequchain$(RESET) $(WELCOME_HEX)|$(RESET) $(GREY)closing$(RESET) $(ITALIC)$(WELCOME_HEX)$(display_msg)$(RESET)")
end

function render_section(title::String, content::Function)
    clear_screen()
    render_header(title)
    
    # Display content directly
    content()
    
    # Show "Press Enter to continue..." message
    _, rows = get_terminal_size()
    message_line = max(4, rows - 2)
    print("\033[$(message_line);1H\033[2KPress Enter to continue...")
    render_footer()
    pause_for_enter(print_message=false)
end

# Convenience wrapper to support render_section("TITLE") do ... end style
function render_section(content::Function, title::String)
    render_section(title, content)
end

function reset_state!()
    BLOCKCHAIN.treasury = Treasury()
    empty!(BLOCKCHAIN.member_coins)
    empty!(BLOCKCHAIN.networks)
    empty!(BLOCKCHAIN.members)
    empty!(BLOCKCHAIN.businesses)
    empty!(BLOCKCHAIN.pledges)
    empty!(BLOCKCHAIN.blockchain)
    BLOCKCHAIN.avg_contrib_rate = 0//1
    MEMBER_COIN_VALUE_CACHE[] = 0//1
    MEMBER_COUNT_CACHE[] = 0
    CURRENT_USER[] = ""
end

# New CLI Command Handlers
# ============================================================================
function handle_login(args::Vector{String})
    if length(args) < 2
        println("Usage: login <member_id>")
        return
    end
    member_id = args[2]
    if haskey(BLOCKCHAIN.members, member_id)
        CURRENT_USER[] = member_id
        println("✅ Logged in as $member_id")
        set_feedback("Logged in as $member_id")
        render_footer()
    else
        println("❌ Member $member_id not found. Use 'join $member_id' to create.")
        set_feedback("Member $member_id not found")
    end
end

function handle_logout()
    if isempty(CURRENT_USER[])
        println("Already logged out")
        set_feedback("No member session active")
        render_footer()
        return
    end
    previous = CURRENT_USER[]
    CURRENT_USER[] = ""
    println("✅ Logged out from $previous")
    set_feedback("Logged out")
    render_footer()
end

function handle_join(args::Vector{String})
    if length(args) < 2
        println("Usage: join <member_id> [deposit]")
        return
    end
    member_id = args[2]
    deposit = length(args) >= 3 ? parse(Float64, args[3]) : 0.0
    
    try
        join_member(member_id, deposit)
        set_feedback("Member $member_id created. Use 'login $member_id' to sign in.")
        render_footer()
    catch e
        println("❌ Error: ", e)
        set_feedback("Join failed: $(string(e))")
    end
end

function handle_create_network(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 4
        println("Usage: create_net <name> <denomination> <rate>")
        return
    end
    name = args[2]
    denom = args[3]
    rate = parse(Float64, args[4])
    
    try
        net_id = create_network(name, denom, rate, CURRENT_USER[])
        println("✅ Network created with ID: $net_id")
    catch e
        println("❌ Error: ", e)
    end
end

function handle_join_network(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        set_feedback("Login required to join a network")
        return
    end
    if length(args) < 2
        println("Usage: join_net <network_id|name>")
        return
    end
    net_identifier = args[2]
    resolved = resolve_network_id(net_identifier)
    if resolved === nothing
        println("❌ Error: Network '$net_identifier' not found")
        set_feedback("Network '$net_identifier' not found")
        return
    end
    net_id = resolved
    
    try
        join_network(CURRENT_USER[], net_id)
        net = BLOCKCHAIN.networks[net_id]
        set_feedback("Joined network $(net.name)")
    catch e
        println("❌ Error: ", e)
        set_feedback("Join network failed: $(string(e))")
    end
end

function handle_transfer_network(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        set_feedback("Login required to transfer networks")
        return
    end
    if length(args) < 3
        println("Usage: transfer_net <from_net_id|name> <to_net_id|name>")
        return
    end
    from_identifier = args[2]
    to_identifier = args[3]
    from_id = resolve_network_id(from_identifier)
    to_id = resolve_network_id(to_identifier)
    if from_id === nothing
        println("❌ Error: Source network '$from_identifier' not found")
        set_feedback("Source network not found")
        return
    end
    if to_id === nothing
        println("❌ Error: Destination network '$to_identifier' not found")
        set_feedback("Destination network not found")
        return
    end
    try
        transfer_network(CURRENT_USER[], from_id, to_id)
        set_feedback("Transferred to $(BLOCKCHAIN.networks[to_id].name)")
        render_footer()
    catch e
        println("❌ Error: ", e)
        set_feedback("Transfer failed: $(string(e))")
        render_footer()
    end
end

function handle_create_business(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 3
        println("Usage: create_bus <name> <network_id>")
        return
    end
    name = args[2]
    net_id = args[3]
    
    try
        bus_id = create_business(name, CURRENT_USER[], net_id)
        println("✅ Business created with ID: $bus_id")
    catch e
        println("❌ Error: ", e)
    end
end

function handle_set_ec(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 3
        println("Usage: set_ec <business_id> <rate>")
        println("Rate must be between 0.00 and 0.05 (0% to 5%)")
        return
    end
    bus_id = args[2]
    rate = parse(Float64, args[3])
    
    try
        set_contrib_rate(bus_id, rate, CURRENT_USER[])
        println("✅ Enterprise contribution rate set to $rate")
    catch e
        println("❌ Error: ", e)
    end
end

function handle_create_pledge(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 6
        println("Usage: create_pledge <name> <target> <network_id> <purpose> <type> [recurring <monthly_amount>]")
        println("Type: 'member' or 'business'")
        println("Note: only business pledges support monthly recurrence; include the monthly amount right after 'recurring'")
        return
    end
    name = args[2]
    target = parse(Float64, args[3])
    net_id = args[4]
    purpose = args[5]
    is_business = args[6] == "business"
    recurring = length(args) > 6 && args[7] == "recurring"
    monthly = length(args) > 7 ? parse(Float64, args[8]) : 0.0
    
    try
        pledge_id = create_pledge(name, target, CURRENT_USER[], net_id, purpose, is_business, recurring, monthly)
        println("✅ Pledge created with ID: $pledge_id")
    catch e
        println("❌ Error: ", e)
    end
end

function handle_support_pledge(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 3
        println("Usage: support <pledge_id> <amount>")
        return
    end
    pledge_id = args[2]
    amount = parse(Float64, args[3])
    
    try
        support_pledge(pledge_id, amount, CURRENT_USER[])
    catch e
        println("❌ Error: ", e)
    end
end

function handle_exit_member(args::Vector{String})
    if length(args) < 2
        println("Usage: exit_member <member_id>")
        return
    end
    member_id = args[2]
    
    try
        refund = exit_member(member_id)
        if CURRENT_USER[] == member_id
            CURRENT_USER[] = ""
        end
        render_footer()
        println("✅ Member exited with refund: $refund")
    catch e
        println("❌ Error: ", e)
    end
end

function handle_withdraw(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 2
        println("Usage: withdraw <amount> [purpose]")
        return
    end
    amount = parse(Float64, args[2])
    purpose = length(args) > 2 ? join(args[3:end], " ") : "external withdrawal"
    
    try
        member_withdraw(CURRENT_USER[], amount, purpose)
        set_feedback("Withdrew $(amount) for $(purpose)")
        render_footer()
    catch e
        println("❌ Error: ", e)
        set_feedback("Withdrawal failed: $(string(e))")
        render_footer()
    end
end

function handle_business_withdraw(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 4
        println("Usage: bus_withdraw <business_id> <amount> <purpose>")
        return
    end
    bus_id = args[2]
    amount = parse(Float64, args[3])
    purpose = join(args[4:end], " ")
    if isempty(purpose)
        purpose = "business expense"
    end
    
    try
        business_withdraw(bus_id, amount, purpose, CURRENT_USER[])
        set_feedback("Business withdrawal processed")
        render_footer()
    catch e
        println("❌ Error: ", e)
        set_feedback("Business withdrawal failed: $(string(e))")
        render_footer()
    end
end

function handle_hire_member(args::Vector{String})
    if isempty(CURRENT_USER[])
        println("Please login first")
        return
    end
    if length(args) < 3
        println("Usage: hire <business_id> <member_id>")
        return
    end
    bus_id = args[2]
    member_id = args[3]
    
    try
        hire_member(bus_id, member_id, CURRENT_USER[])
        set_feedback("Hired $member_id into $bus_id")
        render_footer()
    catch e
        println("❌ Error: ", e)
        set_feedback("Hire failed: $(string(e))")
        render_footer()
    end
end

# Enhanced CLI Main Loop
# ============================================================================
function run_minimal_cli()
    display_welcome(true)
    
    first_command_executed = false

    while true
        try
            # The cursor is already positioned by display_welcome
            line = readline()
            if isempty(line)
                display_welcome(!first_command_executed)
                continue
            end

            raw_parts = split(strip(line))
            if isempty(raw_parts)
                display_welcome(!first_command_executed)
                continue
            end
            parts = String.(raw_parts)
            cmd = lowercase(parts[1])
            clear_feedback()

            if cmd == "exit"
                clear_screen()
                print_exit_banner()   # uses default message (edit print_exit_banner to change)
                break
            elseif cmd == "clear"
                display_welcome(!first_command_executed)
            elseif cmd == "help"
                show_help()
                display_welcome(false)
            elseif cmd == "demo"
                clear_screen()
                render_header("DEMO")
                run_demo()
                first_command_executed = true
                println("\n$(BOLD)Demo finished. Type 'status' to see the result.$(RESET)")
                pause_for_enter()
                display_welcome(false)
            elseif cmd == "status"
                render_section("STATUS", print_status)
                display_welcome(false)
            elseif cmd == "networks"
                render_section("NETWORKS", show_networks)
                display_welcome(false)
            elseif cmd == "businesses"
                render_section("BUSINESSES", show_businesses)
                display_welcome(false)
            elseif cmd == "pledges"
                render_section("PLEDGES", show_pledges)
                display_welcome(false)
            elseif cmd == "balance"
                render_section("BALANCE", () -> show_member_balance(length(parts) > 1 ? parts[2] : ""))
                display_welcome(false)
            elseif cmd == "reset"
                reset_state!()
                first_command_executed = false # Reset demo state
                display_welcome(true)
                render_footer()
            elseif cmd == "example"
                # Guided narrative walkthrough of every command with pagination
                example_content_paginated()
                display_welcome(false)
                
            # New command handlers
            elseif cmd == "login"
                handle_login(parts)
                display_welcome(false)
            elseif cmd == "join"
                handle_join(parts)
                display_welcome(false)
            elseif cmd == "logout"
                handle_logout()
                display_welcome(false)
            elseif cmd == "create_net"
                handle_create_network(parts)
                display_welcome(false)
            elseif cmd == "join_net"
                handle_join_network(parts)
                display_welcome(false)
            elseif cmd == "transfer_net"
                handle_transfer_network(parts)
                display_welcome(false)
            elseif cmd == "create_bus"
                handle_create_business(parts)
                display_welcome(false)
            elseif cmd == "set_ec"
                handle_set_ec(parts)
                display_welcome(false)
            elseif cmd == "create_pledge"
                handle_create_pledge(parts)
                display_welcome(false)
            elseif cmd == "support"
                handle_support_pledge(parts)
                display_welcome(false)
            elseif cmd == "withdraw"
                handle_withdraw(parts)
                display_welcome(false)
            elseif cmd == "bus_withdraw"
                handle_business_withdraw(parts)
                display_welcome(false)
            elseif cmd == "hire"
                handle_hire_member(parts)
                display_welcome(false)
            elseif cmd == "exit_member"
                handle_exit_member(parts)
                display_welcome(false)
            else
                clear_screen()
                render_header()
                println("\n$(BOLD)Unknown command: '$(cmd)'. Type 'help' for options.$(RESET)")
                pause_for_enter()
                display_welcome(!first_command_executed)
            end
            
            if !first_command_executed && cmd != "clear" && cmd != ""
                first_command_executed = true
            end

        catch e
            if isa(e, InterruptException)
                clear_screen()
                print_exit_banner()   # same banner for Interrupt as well
                break
            else
                clear_screen()
                render_header()
                println("\nAn error occurred: ", e)
                pause_for_enter()
                display_welcome(!first_command_executed)
            end
        end
    end
end

# Demo (With New Features)
# ============================================================================
function run_demo()
    println("Resetting state for fresh demo run...")
    reset_state!()
    println("Initializing treasury with founder...")
    init_treasury(150.0, "USD", 1.0, "founder")
    
    println("Adding members...")
    join_member("alice", 100.0)
    join_member("bob", 25.0)
    join_member("carla", 75.0)
    join_member("dave", 10.0)

    println("Simulating member withdrawal...")
    member_withdraw("alice", 25.0, "groceries & essentials")
    
    println("Creating networks...")
    usd_net = create_network("USD_Net", "USD", 1.0, "founder")
    zar_net = create_network("ZAR_Net", "ZAR", 17.35, "alice")
    
    println("Joining and transferring networks...")
    join_network("alice", usd_net)
    join_network("bob", usd_net)
    join_network("carla", usd_net)
    join_network("dave", zar_net)
    join_network("founder", zar_net)
    println("Relocating bob from USD_Net to ZAR_Net for cross-border work...")
    transfer_network("bob", usd_net, zar_net)
    
    println("Launching businesses in both networks...")
    usd_business = create_business("EquiTech", "founder", usd_net)
    set_contrib_rate(usd_business, 0.03, "founder")
    hire_member(usd_business, "alice", "founder")
    hire_member(usd_business, "carla", "founder")
    business_withdraw(usd_business, 2.0, "prototype materials", "founder")
    
    zar_business = create_business("UbuntuWorks", "alice", zar_net)
    set_contrib_rate(zar_business, 0.025, "alice")
    hire_member(zar_business, "bob", "alice")
    hire_member(zar_business, "dave", "alice")
    business_withdraw(zar_business, 1.5, "community rollout", "alice")
    
    println("Creating pledges...")
    member_pledge = create_pledge("HolidayFund", 1000.0, "alice", zar_net, "Overseas travel & immigration", false)
    support_pledge(member_pledge, 40.0, "carla")
    support_pledge(member_pledge, 35.0, "dave")
    
    bus_pledge = create_pledge("StartupBoost", 2000.0, "founder", usd_net, "Additional funding", true, true, 120.0)
    support_pledge(bus_pledge, 60.0, "alice")
    support_pledge(bus_pledge, 45.0, "bob")
    
    println("Simulating time passage...")
    sleep(2)
    process_recurring_pledges()
    
    print_status()
    println("✅ Demo: Equality maintained across five members, dual businesses, and cross-network transfers")
end

if abspath(PROGRAM_FILE) == @__FILE__
    # Default to the interactive CLI when no arguments are given,
    # or when the explicit "cli" argument is provided. Preserve
    # the previous behavior for other arguments (run_demo).
    if isempty(ARGS) || (length(ARGS) >= 1 && ARGS[1] == "cli")
        run_minimal_cli()
    else
        run_demo()
    end
end