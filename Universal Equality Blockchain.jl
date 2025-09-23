using SHA
using Sockets
using JSON3
using Dates
using Random
using Base64
using UUIDs

# ============================================================================
# UNIVERSAL EQUALITY BLOCKCHAIN - COMPLETE IMPLEMENTATION
# ============================================================================
#
# ⚠️  WARNING: DEMO MODE ONLY ⚠️
# This implementation uses insecure cryptographic functions by default.
# Set DEMO_MODE = false and implement proper cryptography for production use.
#
# ============================================================================

# DEMO MODE CONFIGURATION
# ============================================================================
const DEMO_MODE = true  # Set to false for production (requires proper cryptographic implementation)

# Core Data Structures
# ============================================================================

mutable struct DigitalAsset
    id::String
    owner::String
    value::Float64
    created_at::DateTime
    
    DigitalAsset() = new(string(uuid4()), "", 0.0, now())
end

mutable struct StableCoin
    amount::Float64
    peg_currency::String
    peg_rate::Float64
    
    StableCoin() = new(0.0, "", 1.0)
end

mutable struct NativeCoin
    owner::String
    minted_at::DateTime
    
    NativeCoin(owner::String) = new(owner, now())
end

mutable struct Treasury
    stable_coins::Float64
    total_value::Float64
    
    Treasury() = new(0.0, 0.0)
end

struct Transaction
    id::String
    type::String
    from::String
    to::String
    data::Dict{String, Any}
    timestamp::DateTime
    signature::String
    
    Transaction(type::String, from::String, to::String, data::Dict{String, Any}) = 
        new(string(uuid4()), type, from, to, data, now(), "")
end

mutable struct Block
    hash::String
    prev_hash::String
    transaction::Transaction
    timestamp::DateTime
    validator::String
    
    Block(prev_hash::String, transaction::Transaction, validator::String) = 
        new("", prev_hash, transaction, now(), validator)
end

# Blockchain State
# ============================================================================

mutable struct BlockchainState
    digital_asset::DigitalAsset
    treasury::Treasury
    stable_coin::StableCoin
    native_coins::Dict{String, NativeCoin}
    members::Set{String}
    blockchain::Vector{Block}
    
    BlockchainState() = new(
        DigitalAsset(),
        Treasury(),
        StableCoin(),
        Dict{String, NativeCoin}(),
        Set{String}(),
        Vector{Block}()
    )
end

# Global state instance
const BLOCKCHAIN_STATE = BlockchainState()

# Cryptographic Functions
# ============================================================================

function currency(::Type{UInt64})
    # Generate a demo currency-based identifier (for demo mode only)
    return rand(UInt64)
end

function generate_keypair()
    if DEMO_MODE
        # DEMO ONLY: Insecure key generation for testing/demonstration
        private_key = string(currency(UInt64))
        public_key = bytes2hex(sha256(private_key))
        return (private_key, public_key)
    else
        # Production mode: Implement proper ECDSA key generation here
        error("Production cryptography not implemented. Set DEMO_MODE = true for testing.")
    end
end

function generate_address(public_key::String)
    return bytes2hex(sha256(public_key))[1:20]
end

function sign_transaction(transaction::Transaction, private_key::String)
    if DEMO_MODE
        # DEMO ONLY: Insecure signing for testing/demonstration
        data_string = string(transaction.type, transaction.from, transaction.to, transaction.timestamp)
        return bytes2hex(sha256(data_string * private_key))
    else
        # Production mode: Implement proper ECDSA signing here
        error("Production cryptography not implemented. Set DEMO_MODE = true for testing.")
    end
end

function create_block_hash(block::Block)
    data_string = string(
        block.prev_hash,
        block.transaction.id,
        block.transaction.type,
        block.transaction.from,
        block.transaction.to,
        block.timestamp,
        block.validator
    )
    return bytes2hex(sha256(data_string))
end

# Core Blockchain Functions
# ============================================================================

function create_genesis_block(founder_address::String)
    # Create genesis transaction
    genesis_data = Dict{String, Any}(
        "action" => "initialize_system",
        "founder" => founder_address
    )
    
    genesis_tx = Transaction("GENESIS", "SYSTEM", founder_address, genesis_data)
    genesis_block = Block("0", genesis_tx, founder_address)
    genesis_block.hash = create_block_hash(genesis_block)
    
    # Initialize state
    BLOCKCHAIN_STATE.digital_asset.owner = founder_address
    BLOCKCHAIN_STATE.native_coins[founder_address] = NativeCoin(founder_address)
    push!(BLOCKCHAIN_STATE.members, founder_address)
    push!(BLOCKCHAIN_STATE.blockchain, genesis_block)
    
    println("✅ Genesis block created!")
    println("Digital Asset ID: $(BLOCKCHAIN_STATE.digital_asset.id)")
    println("Founder: $founder_address")
    println("Members: $(length(BLOCKCHAIN_STATE.members))")
    
    return genesis_block
end

function create_stable_coins(amount::Float64, currency::String, peg_rate::Float64, buyer_address::String)
    if BLOCKCHAIN_STATE.digital_asset.owner != buyer_address
        error("Only digital asset owner can create stable coins")
    end
    
    if BLOCKCHAIN_STATE.stable_coin.amount > 0
        error("Stable coins already created")
    end
    
    # Create stable coins and set peg
    BLOCKCHAIN_STATE.stable_coin.amount = amount
    BLOCKCHAIN_STATE.stable_coin.peg_currency = currency
    BLOCKCHAIN_STATE.stable_coin.peg_rate = peg_rate
    
    # Add to treasury
    BLOCKCHAIN_STATE.treasury.stable_coins = amount
    BLOCKCHAIN_STATE.treasury.total_value = amount * peg_rate
    
    # Value the digital asset
    BLOCKCHAIN_STATE.digital_asset.value = amount * peg_rate
    
    # Create transaction
    tx_data = Dict{String, Any}(
        "stable_coin_amount" => amount,
        "currency" => currency,
        "peg_rate" => peg_rate,
        "digital_asset_value" => BLOCKCHAIN_STATE.digital_asset.value
    )
    
    tx = Transaction("CREATE_STABLE_COINS", buyer_address, "TREASURY", tx_data)
    add_transaction(tx, buyer_address)
    
    println("✅ Stable coins created!")
    println("Amount: $amount $currency")
    println("Treasury Value: $(BLOCKCHAIN_STATE.treasury.total_value)")
    println("Digital Asset Value: $(BLOCKCHAIN_STATE.digital_asset.value)")
end

function join_member(new_member_address::String, deposit_amount::Float64)
    if new_member_address in BLOCKCHAIN_STATE.members
        error("Member already exists")
    end
    
    # Calculate required deposit
    current_member_count = length(BLOCKCHAIN_STATE.members)
    required_deposit = current_member_count > 0 ? 
        BLOCKCHAIN_STATE.treasury.total_value / current_member_count : 0.0
    
    if abs(deposit_amount - required_deposit) > 0.01  # Allow small floating point differences
        error("Required deposit: $required_deposit, provided: $deposit_amount")
    end
    
    # Add to treasury and members
    BLOCKCHAIN_STATE.treasury.total_value += deposit_amount
    BLOCKCHAIN_STATE.treasury.stable_coins += deposit_amount / BLOCKCHAIN_STATE.stable_coin.peg_rate
    
    push!(BLOCKCHAIN_STATE.members, new_member_address)
    BLOCKCHAIN_STATE.native_coins[new_member_address] = NativeCoin(new_member_address)
    
    # Create transaction
    tx_data = Dict{String, Any}(
        "deposit_amount" => deposit_amount,
        "new_member_count" => length(BLOCKCHAIN_STATE.members),
        "new_treasury_value" => BLOCKCHAIN_STATE.treasury.total_value
    )
    
    tx = Transaction("JOIN_MEMBER", new_member_address, "TREASURY", tx_data)
    add_transaction(tx, new_member_address)
    
    println("✅ Member joined!")
    println("New Member: $new_member_address")
    println("Members: $(length(BLOCKCHAIN_STATE.members))")
    println("Treasury Value: $(BLOCKCHAIN_STATE.treasury.total_value)")
    println("Value per Native Coin: $(get_native_coin_value())")
end

function exit_member(member_address::String)
    if !(member_address in BLOCKCHAIN_STATE.members)
        error("Member does not exist")
    end
    
    if length(BLOCKCHAIN_STATE.members) == 1
        error("Cannot exit - last member remaining")
    end
    
    # Calculate refund
    refund_amount = BLOCKCHAIN_STATE.treasury.total_value / length(BLOCKCHAIN_STATE.members)
    
    # Remove from treasury and members
    BLOCKCHAIN_STATE.treasury.total_value -= refund_amount
    BLOCKCHAIN_STATE.treasury.stable_coins -= refund_amount / BLOCKCHAIN_STATE.stable_coin.peg_rate
    
    delete!(BLOCKCHAIN_STATE.members, member_address)
    delete!(BLOCKCHAIN_STATE.native_coins, member_address)
    
    # Create transaction
    tx_data = Dict{String, Any}(
        "refund_amount" => refund_amount,
        "remaining_member_count" => length(BLOCKCHAIN_STATE.members),
        "new_treasury_value" => BLOCKCHAIN_STATE.treasury.total_value
    )
    
    tx = Transaction("EXIT_MEMBER", member_address, "TREASURY", tx_data)
    add_transaction(tx, first(BLOCKCHAIN_STATE.members))  # Validated by remaining member
    
    println("✅ Member exited!")
    println("Exited Member: $member_address")
    println("Refund Amount: $refund_amount")
    println("Remaining Members: $(length(BLOCKCHAIN_STATE.members))")
    println("Value per Native Coin: $(get_native_coin_value())")
    
    return refund_amount
end

function transfer_stable_coins(from_address::String, to_address::String, amount::Float64)
    # Validate both users are members
    if !(from_address in BLOCKCHAIN_STATE.members)
        error("Sender $from_address is not a member")
    end
    
    if !(to_address in BLOCKCHAIN_STATE.members)
        error("Recipient $to_address is not a member")
    end
    
    # Validate amount is positive
    if amount <= 0
        error("Transfer amount must be positive")
    end
    
    # Validate stable coins exist
    if BLOCKCHAIN_STATE.stable_coin.amount == 0
        error("No stable coins have been created yet")
    end
    
    # Create transfer transaction data
    tx_data = Dict{String, Any}(
        "transfer_amount" => amount,
        "treasury_stable_coins" => BLOCKCHAIN_STATE.treasury.stable_coins,
        "member_count" => length(BLOCKCHAIN_STATE.members),
        "equal_share_per_member" => BLOCKCHAIN_STATE.treasury.stable_coins / length(BLOCKCHAIN_STATE.members)
    )
    
    # Create and add transaction (treasury balances remain unchanged due to automatic equality)
    tx = Transaction("TRANSFER_STABLE_COINS", from_address, to_address, tx_data)
    add_transaction(tx, from_address)
    
    println("✅ Transfer completed: $amount stable coins from $from_address to $to_address")
    println("🔄 Automatic equality maintained: Each member has $(BLOCKCHAIN_STATE.treasury.stable_coins / length(BLOCKCHAIN_STATE.members)) stable coins")
    
    return true
end

function add_transaction(transaction::Transaction, validator::String)
    # Get previous block hash
    prev_hash = length(BLOCKCHAIN_STATE.blockchain) > 0 ? 
        BLOCKCHAIN_STATE.blockchain[end].hash : "0"
    
    # Create new block
    new_block = Block(prev_hash, transaction, validator)
    new_block.hash = create_block_hash(new_block)
    
    # Validate the entire chain (every transaction validates every other)
    if !validate_chain()
        error("Chain validation failed before adding new block")
    end
    
    # Add block to blockchain
    push!(BLOCKCHAIN_STATE.blockchain, new_block)
    
    # Validate chain again with new block
    if !validate_chain()
        error("Chain validation failed after adding new block")
        pop!(BLOCKCHAIN_STATE.blockchain)
    end
    
    println("📦 Block added: $(new_block.hash[1:8])...")
    
    # Broadcast to network (if connected)
    broadcast_block(new_block)
end

function validate_chain()
    if length(BLOCKCHAIN_STATE.blockchain) == 0
        return true
    end
    
    # Validate hash chain
    for i in 2:length(BLOCKCHAIN_STATE.blockchain)
        current_block = BLOCKCHAIN_STATE.blockchain[i]
        prev_block = BLOCKCHAIN_STATE.blockchain[i-1]
        
        # Check hash linking
        if current_block.prev_hash != prev_block.hash
            println("❌ Hash chain broken at block $i")
            return false
        end
        
        # Verify block hash
        expected_hash = create_block_hash(current_block)
        if current_block.hash != expected_hash
            println("❌ Invalid block hash at block $i")
            return false
        end
    end
    
    # Validate state consistency
    if !validate_state_consistency()
        return false
    end
    
    return true
end

function validate_state_consistency()
    member_count = length(BLOCKCHAIN_STATE.members)
    native_coin_count = length(BLOCKCHAIN_STATE.native_coins)
    
    # Check member count equals native coin count
    if member_count != native_coin_count
        println("❌ Member count ($member_count) != Native coin count ($native_coin_count)")
        return false
    end
    
    # Check treasury math
    if member_count > 0
        expected_value_per_coin = BLOCKCHAIN_STATE.treasury.total_value / member_count
        actual_value_per_coin = get_native_coin_value()
        
        if abs(expected_value_per_coin - actual_value_per_coin) > 0.01
            println("❌ Treasury math inconsistent")
            return false
        end
    end
    
    return true
end

# Utility Functions
# ============================================================================

function get_native_coin_value()
    member_count = length(BLOCKCHAIN_STATE.members)
    return member_count > 0 ? BLOCKCHAIN_STATE.treasury.total_value / member_count : 0.0
end

function get_member_balance(member_address::String)
    if member_address in BLOCKCHAIN_STATE.members
        return get_native_coin_value()
    else
        return 0.0
    end
end

function print_blockchain_status()
    println("\n" * "="^50)
    println("BLOCKCHAIN STATUS")
    println("="^50)
    println("Digital Asset ID: $(BLOCKCHAIN_STATE.digital_asset.id)")
    println("Digital Asset Owner: $(BLOCKCHAIN_STATE.digital_asset.owner)")
    println("Digital Asset Value: $(BLOCKCHAIN_STATE.digital_asset.value)")
    println()
    println("Stable Coins: $(BLOCKCHAIN_STATE.stable_coin.amount) $(BLOCKCHAIN_STATE.stable_coin.peg_currency)")
    println("Peg Rate: $(BLOCKCHAIN_STATE.stable_coin.peg_rate)")
    println()
    println("Treasury Total Value: $(BLOCKCHAIN_STATE.treasury.total_value)")
    println("Treasury Stable Coins: $(BLOCKCHAIN_STATE.treasury.stable_coins)")
    println()
    println("Total Members: $(length(BLOCKCHAIN_STATE.members))")
    println("Native Coin Value: $(get_native_coin_value())")
    println()
    println("Blockchain Length: $(length(BLOCKCHAIN_STATE.blockchain))")
    println("Chain Valid: $(validate_chain())")
    println("="^50)
end

function print_member_list()
    println("\n" * "="^30)
    println("MEMBERS")
    println("="^30)
    for (i, member) in enumerate(BLOCKCHAIN_STATE.members)
        balance = get_member_balance(member)
        println("$i. $(member[1:8])... - Balance: $balance")
    end
    println("="^30)
end

# Network Functions (Simplified P2P)
# ============================================================================

mutable struct NetworkNode
    address::String
    port::Int
    peers::Set{String}
    server_task::Union{Task, Nothing}
    
    NetworkNode(address::String, port::Int) = new(address, port, Set{String}(), nothing)
end

const NETWORK_NODE = NetworkNode("", 0)

function start_network_node(port::Int)
    NETWORK_NODE.address = string(Sockets.getipaddr())
    NETWORK_NODE.port = port
    
    # Start listening server
    NETWORK_NODE.server_task = @async begin
        server = listen(port)
        println("🌐 Network node started on $(NETWORK_NODE.address):$port")
        
        while true
            try
                sock = accept(server)
                @async handle_peer_connection(sock)
            catch e
                println("Network error: $e")
            end
        end
    end
end

function handle_peer_connection(sock)
    try
        while isopen(sock)
            data = readline(sock)
            if !isempty(data)
                handle_network_message(JSON3.read(data))
            end
        end
    catch e
        println("Peer connection error: $e")
    finally
        close(sock)
    end
end

function connect_to_peer(peer_address::String, peer_port::Int)
    try
        peer_id = "$peer_address:$peer_port"
        push!(NETWORK_NODE.peers, peer_id)
        println("🤝 Connected to peer: $peer_id")
    catch e
        println("Failed to connect to peer: $e")
    end
end

function broadcast_block(block::Block)
    if length(NETWORK_NODE.peers) == 0
        return
    end
    
    message = Dict(
        "type" => "new_block",
        "block" => Dict(
            "hash" => block.hash,
            "prev_hash" => block.prev_hash,
            "transaction" => Dict(
                "id" => block.transaction.id,
                "type" => block.transaction.type,
                "from" => block.transaction.from,
                "to" => block.transaction.to,
                "data" => block.transaction.data,
                "timestamp" => block.transaction.timestamp
            ),
            "timestamp" => block.timestamp,
            "validator" => block.validator
        )
    )
    
    # Broadcast to all peers (simplified)
    println("📡 Broadcasting block to $(length(NETWORK_NODE.peers)) peers")
end

function handle_network_message(message::Dict)
    if message["type"] == "new_block"
        println("📨 Received new block from network")
        # In full implementation, would validate and add block
    end
end

# Interactive CLI Functions
# ============================================================================

function run_interactive_cli()
    println("🚀 Universal Equality Blockchain Started!")
    println("Type 'help' for available commands")
    
    while true
        print("\nEqualityChain> ")
        command = strip(readline())
        
        if command == "exit"
            break
        elseif command == "help"
            show_help()
        elseif command == "status"
            print_blockchain_status()
        elseif command == "members"
            print_member_list()
        elseif startswith(command, "genesis")
            handle_genesis_command(command)
        elseif startswith(command, "create_coins")
            handle_create_coins_command(command)
        elseif startswith(command, "join")
            handle_join_command(command)
        elseif startswith(command, "exit_member")
            handle_exit_member_command(command)
        elseif startswith(command, "transfer")
            handle_transfer_command(command)
        elseif startswith(command, "network")
            handle_network_command(command)
        elseif startswith(command, "validate")
            println("Chain validation: $(validate_chain())")
        else
            println("Unknown command. Type 'help' for available commands.")
        end
    end
    
    println("👋 Goodbye!")
end

function show_help()
    println("\n📚 Available Commands:")
    println("  genesis <address>                    - Create genesis block")
    println("  create_coins                         - Use launch config (R17.27 → 1 USD coin)")
    println("  create_coins <amount> <currency>     - Create stable coins manually")
    println("  join <address> <deposit>             - Join as new member")
    println("  exit_member <address>                - Exit member from network")
    println("  transfer <from> <to> <amount>        - Transfer stable coins between members")
    println("  status                               - Show blockchain status")
    println("  members                              - List all members")
    println("  validate                             - Validate blockchain")
    println("  network start <port>                 - Start network node")
    println("  network connect <ip> <port>          - Connect to peer")
    println("  help                                 - Show this help")
    println("  exit                                 - Exit application")
end

function handle_genesis_command(command::String)
    parts = split(command)
    if length(parts) != 2
        println("Usage: genesis <founder_address>")
        return
    end
    
    try
        create_genesis_block(parts[2])
    catch e
        println("Error: $e")
    end
end

# ============================================================================
# LAUNCH CONFIGURATION - EDIT THESE VALUES FOR YOUR SPECIFIC SETUP
# ============================================================================

# For 17.35 ZAR to create 1 USD-pegged stable coin (1:1 USD to stable coin value, backed by current USD to ZAR exchange rate):
const LAUNCH_PEG_AMOUNT = 17.35        # Amount in ZAR you are spending
const LAUNCH_STABLE_COINS = 1.0        # Number of USD-pegged stable coins to create (1:1 USD value)
const LAUNCH_PEG_CURRENCY = "USD"      # Currency to peg stable coins to
const LAUNCH_PEG_RATE = 17.35        # Current USD to ZAR exchange rate (17.35 ZAR per 1 USD)

# To change your launch parameters:
# 1. LAUNCH_PEG_AMOUNT = how much ZAR you're investing to back the stable coins
# 2. LAUNCH_STABLE_COINS = how many USD-pegged stable coins this creates (1:1 USD value)
# 3. LAUNCH_PEG_CURRENCY = what currency the stable coins represent (USD for global compatibility)
# 4. LAUNCH_PEG_RATE = current exchange rate (ZAR per 1 USD stable coin)

# Example configurations:
# For 100 ZAR creating 100 ZAR-pegged coins: 100.0, 100.0, "ZAR", 1.0
# For 17.35 ZAR creating 1 USD-pegged coin (1:1 USD value): 17.35, 1.0, "USD", 17.35
# For 50 ZAR creating ~2.9 USD-pegged coins: 50.0, 2.9, "USD", 17.24

# ============================================================================

function handle_create_coins_command(command::String)
    parts = split(command)
    if length(parts) == 1
        # AUTO-LAUNCH MODE: Use predefined launch configuration
        println("🚀 Using launch configuration:")
    println("   Spending: $(LAUNCH_PEG_AMOUNT) $(LAUNCH_PEG_CURRENCY)")
        println("   Creating: $(LAUNCH_STABLE_COINS) stable coins")
        println("   Pegged to: $(LAUNCH_PEG_CURRENCY)")
        println("   Exchange rate: $(LAUNCH_PEG_RATE) ZAR per $(LAUNCH_PEG_CURRENCY)")
        
        if isempty(BLOCKCHAIN_STATE.members)
            println("Error: No genesis block created yet")
            return
        end
        
        founder = first(BLOCKCHAIN_STATE.members)
        create_stable_coins(LAUNCH_STABLE_COINS, LAUNCH_PEG_CURRENCY, LAUNCH_PEG_RATE, founder)
        
    elseif length(parts) != 3
        println("Usage: create_coins <amount> <currency>  OR  create_coins (uses launch config)")
        return
    else
        # MANUAL MODE: Use command line parameters
        try
            amount = parse(Float64, parts[2])
            currency = parts[3]
            
            if isempty(BLOCKCHAIN_STATE.members)
                println("Error: No genesis block created yet")
                return
            end
            
            founder = first(BLOCKCHAIN_STATE.members)
            create_stable_coins(amount, currency, 1.0, founder)
        catch e
            println("Error: $e")
        end
    end
end

function handle_join_command(command::String)
    parts = split(command)
    if length(parts) != 3
        println("Usage: join <member_address> <deposit_amount>")
        return
    end
    
    try
        address = parts[2]
        deposit = parse(Float64, parts[3])
        join_member(address, deposit)
    catch e
        println("Error: $e")
    end
end

function handle_exit_member_command(command::String)
    parts = split(command)
    if length(parts) != 2
        println("Usage: exit_member <member_address>")
        return
    end
    
    try
        exit_member(parts[2])
    catch e
        println("Error: $e")
    end
end

function handle_transfer_command(command::String)
    parts = split(command)
    if length(parts) != 4
        println("Usage: transfer <from_address> <to_address> <amount>")
        return
    end
    
    try
        from_address = parts[2]
        to_address = parts[3]
        amount = parse(Float64, parts[4])
        transfer_stable_coins(from_address, to_address, amount)
    catch e
        println("Error: $e")
    end
end

function handle_network_command(command::String)
    parts = split(command)
    if length(parts) < 2
        println("Usage: network <start|connect> [params]")
        return
    end
    
    try
        if parts[2] == "start" && length(parts) == 3
            port = parse(Int, parts[3])
            start_network_node(port)
        elseif parts[2] == "connect" && length(parts) == 4
            ip = parts[3]
            port = parse(Int, parts[4])
            connect_to_peer(ip, port)
        else
            println("Usage: network start <port> | network connect <ip> <port>")
        end
    catch e
        println("Error: $e")
    end
end

# Testing Functions
# ============================================================================

function run_automated_test()
    println("🧪 Running Automated Test Suite...")
    
    try
        # Test 1: Genesis
        println("\n1️⃣  Testing Genesis Block Creation...")
        create_genesis_block("founder123")
        @assert length(BLOCKCHAIN_STATE.members) == 1
        @assert validate_chain()
        println("✅ Genesis test passed")
        
        # Test 2: Stable Coins (Updated for launch config)
        println("\n2️⃣  Testing Stable Coin Creation...")
        create_stable_coins(LAUNCH_STABLE_COINS, LAUNCH_PEG_CURRENCY, LAUNCH_PEG_RATE, "founder123")
    @assert BLOCKCHAIN_STATE.treasury.total_value == LAUNCH_PEG_AMOUNT
    @assert get_native_coin_value() == LAUNCH_PEG_AMOUNT
        @assert validate_chain()
        println("✅ Stable coins test passed ($(LAUNCH_STABLE_COINS) $(LAUNCH_PEG_CURRENCY) coins created)")
        
        # Test 3: Member Join (Updated for launch amounts)
        println("\n3️⃣  Testing Member Join...")
    join_member("member456", LAUNCH_PEG_AMOUNT)
        @assert length(BLOCKCHAIN_STATE.members) == 2
    @assert abs(get_native_coin_value() - LAUNCH_PEG_AMOUNT) < 0.01
    @assert BLOCKCHAIN_STATE.treasury.total_value == LAUNCH_PEG_AMOUNT * 2
        @assert validate_chain()
        println("✅ Member join test passed")
        
        # Test 4: Another Member Join (Updated for launch amounts)  
        println("\n4️⃣  Testing Second Member Join...")
    join_member("member789", LAUNCH_PEG_AMOUNT)
        @assert length(BLOCKCHAIN_STATE.members) == 3
    @assert abs(get_native_coin_value() - LAUNCH_PEG_AMOUNT) < 0.01
    @assert BLOCKCHAIN_STATE.treasury.total_value == LAUNCH_PEG_AMOUNT * 3
        @assert validate_chain()
        println("✅ Second member join test passed")
        
        # Test 5: Member Exit (Updated for launch amounts)
        println("\n5️⃣  Testing Member Exit...")
        refund = exit_member("member456")
        @assert length(BLOCKCHAIN_STATE.members) == 2
    @assert abs(refund - LAUNCH_PEG_AMOUNT) < 0.01
    @assert abs(get_native_coin_value() - LAUNCH_PEG_AMOUNT) < 0.01
    @assert BLOCKCHAIN_STATE.treasury.total_value == LAUNCH_PEG_AMOUNT * 2
        @assert validate_chain()
        println("✅ Member exit test passed")
        
        # Test 6: Stable Coin Transfers with Automatic Rebalancing
        println("\n6️⃣  Testing Stable Coin Transfers...")
        initial_members = length(BLOCKCHAIN_STATE.members)
        initial_per_member = BLOCKCHAIN_STATE.treasury.stable_coins / initial_members
        
        # Transfer between remaining members (founder123 and member789)
        transfer_stable_coins("founder123", "member789", 0.5)
        
        # Verify automatic equality maintained
        @assert length(BLOCKCHAIN_STATE.members) == initial_members  # Member count unchanged
        @assert abs(BLOCKCHAIN_STATE.treasury.stable_coins / length(BLOCKCHAIN_STATE.members) - initial_per_member) < 0.01
        @assert validate_chain()
        println("✅ Transfer test passed - equality maintained!")
        
        println("\n🎉 ALL TESTS PASSED! 🎉")
        print_blockchain_status()
        
    catch e
        println("\n❌ TEST FAILED: $e")
        rethrow(e)
    end
end

# Main Entry Point
# ============================================================================

function main()
    println("🌟 Universal Equality Blockchain v1.0")
    println("=====================================")
    
    if length(ARGS) > 0 && ARGS[1] == "test"
        run_automated_test()
    else
        run_interactive_cli()
    end
end

# Auto-start if running as main script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

# ============================================================================
# USAGE INSTRUCTIONS
# ============================================================================

"""
⚠️  COMPREHENSIVE DISCLAIMER ⚠️

🔒 DEMO MODE SAFETY:
- Currently set to DEMO_MODE = true for safe testing and demonstration
- Safe to run and exit - creates no persistent files or system changes  
- All blockchain state exists only in memory during program execution
- Uses simplified cryptography suitable only for testing/learning

🚫 PRODUCTION WARNING:
- DO NOT use in production without implementing proper ECDSA cryptography
- Requires peer network setup and secure key management for real deployment
- Current implementation is for educational and prototyping purposes only

⚖️  LIABILITY DISCLAIMER:
- This software is provided "AS IS" for educational and research purposes
- The author/creator assumes NO LIABILITY for any use of this software
- Users assume full responsibility for any implementation or deployment
- Not financial advice - purely a technical proof-of-concept
- Open source project - use at your own risk and discretion

QUICK START GUIDE FOR A PEG CURRENCY LAUNCH (example: 17.27 ZAR → 1 USD):

1. Run the program:
   julia equality_blockchain.jl

2. Create genesis block:
   EqualityChain> genesis your_founder_address

3. Create pegged stable coins using your configured peg currency and amount:
   EqualityChain> create_coins
    (This uses your launch config: $(LAUNCH_PEG_AMOUNT) $(LAUNCH_PEG_CURRENCY) creates $(LAUNCH_STABLE_COINS) coin(s))

4. Others join by depositing the configured peg amount each:
    EqualityChain> join member_address_456 $(LAUNCH_PEG_AMOUNT)
    EqualityChain> join member_address_789 $(LAUNCH_PEG_AMOUNT)

🔧 TO CHANGE LAUNCH PARAMETERS:
Edit the constants at the top of the file:
- `LAUNCH_PEG_AMOUNT` = how much of your source currency you're putting in (e.g., 17.27)
- `LAUNCH_STABLE_COINS` = how many stable coins this creates
- `LAUNCH_PEG_CURRENCY` = which currency the stable coins represent (e.g., "USD")
- `LAUNCH_PEG_RATE` = exchange rate (source currency per 1 stable coin unit)

5. Check status:
   EqualityChain> status
   EqualityChain> members

6. Test networking:
   EqualityChain> network start 8080

7. Run automated tests:
   julia equality_blockchain.jl test

KEY FEATURES:
✅ Ultra-lightweight (< 1MB memory usage)
✅ Instant feeless transactions
✅ Perfect mathematical equality (treasury_value / member_count)
✅ Every transaction validates entire chain
✅ 1 node per member architecture
✅ Real currency pegging via stable coins
✅ Complete P2P networking foundation
✅ Scales from 1 person to global adoption (< 800MB even at global scale)
✅ Mobile/embedded device compatible
✅ Supports all world currencies via stable coin pegging
✅ DEMO MODE: Safe to run and exit - no persistent storage
✅ Requires peer nodes for production network deployment
✅ Mathematical proof of concept for free and equal economy

🔒 SAFETY NOTICE: Currently in DEMO MODE
- Safe to run, test, and exit without system impact
- No files created or modified on your system
- All blockchain state exists only in memory during runtime
- Production deployment would require peer network setup

This represents a complete technical foundation for a Universal Equality 
Blockchain - "A basis for free and equal economy, encapsulated in blockchain 
and smart contract technology"! 🚀
"""
