module AequChain

# Re-exports for public API
export AccountID, Hash, BlockHeader, SendBlock, ReceiveBlock, QuorumCert
export AccountState, apply_send!, apply_receive!
export Committee, CommitteeMember, select_committee
export PartialVote, aggregate_qc
export rate_limit_check!, maybe_do_pow!
export hash_block
export NodeConfig, InMemoryNode, register_account!, submit_payment!, get_account_balance
export list_blocks, list_quorum_certs, metrics_snapshot, projected_capacity, memory_breakdown

include("types/Types.jl")
include("network/Messages.jl")
using .Messages: hash_block
include("state/State.jl")
include("consensus/CommitteeSelection.jl")
include("consensus/Aggregation.jl")
include("anti_spam/RateLimiter.jl")
include("anti_spam/PoW.jl")
include("network/Gossip.jl")
include("identity/PoP.jl")
include("node/TestnetNode.jl")

using .TestnetNode: NodeConfig, InMemoryNode, register_account!, submit_payment!, get_account_balance
using .TestnetNode: list_blocks, list_quorum_certs, metrics_snapshot, projected_capacity, memory_breakdown

end # module