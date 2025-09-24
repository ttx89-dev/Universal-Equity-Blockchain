# aequchain readme

aequchain — universal equidistributed blockchain (aequchain)

summary
- aequchain is a demonstration implementation of the universal equidistributed blockchain (ueb) concepts.
- it uses exact monetary precision via `rational{bigint}` and models global member coins, networks, businesses, pledges, and a tiny immutable block log for auditability.

quick start
- run the demo script (runs the built-in demo flow):

```bash
julia aequchain.jl
```

- or include and call functions from the julia REPL or a julia project:

```bash
julia --project -e 'include("aequchain.jl"); aequchain.run_demo()'
```

core functions (quick reference)
- `init_treasury(deposit::float64, currency::string, rate::float64, founder::string)` — initialize treasury and create founder member.
- `join_member(id::string, deposit::float64)` — add a new member by depositing exact value.
- `exit_member(id::string)` — member exit and refund of equal-value share.
- `transfer(from::string, to::string, amount::float64)` — logs a transfer (equality-preserving demo operation).
- `create_network(name::string, denom::string, rate::float64, creator::string)` — create a network with a denomination.
- `join_network(member_id::string, net_id::string)` — member joins a network.
- `create_business(name::string, owner::string, net_id::string)` — create a business inside a network.
- `set_contrib_rate(bus_id::string, rate::float64, owner::string)` — set business contribution rate (0 - 5%).
- `business_spend(bus_id::string, amount::float64, purpose::string, owner::string)` — log business spending (checks allocation and 30-day limit).
- `create_pledge(name::string, target::float64, creator::string, net_id::string, purpose::string, is_business::bool, recurring::bool=false, monthly::float64=0.0)` — create member or business pledge.
- `support_pledge(pledge_id::string, amount::float64, supporter::string)` — support pledge (records spend, can mark completed).
- `print_status()` — print a brief current state summary.
- `run_demo()` — run the included demo flow.

data structures
- `treasury` — global stablecoins, peg currency, peg rate.
- `membercoin` — non-transferable membership coin (owner + minted_at).
- `network` — networks with denom and denom_rate.
- `member` — member metadata, networks, businesses, 30-day spend history and allowance.
- `business` — business metadata, contrib rate, allocation budget and employees.
- `pledge` — pledges with supporters, recurring flags and monthly amounts.
- `transaction` / `block` — small immutable transaction and block structure used for audit logging in-memory.

notes & caveats
- demo mode: the included file runs in `demo_mode` and keeps all state in-memory; there is no persistent database.
- exact math: monetary values use `rational{bigint}` with cent precision to avoid floating-point rounding.
- recurring pledges: recurring behavior is simulated in the demo; production systems must schedule and persist recurring payouts.
- safety: members have a 30-day spend limit equal to their exact equal share; functions validate and record spends.
- this readme was added without modifying `aequchain.jl`.

license & attribution
- the repository currently does not attach a license file; please add an appropriate license at the repository root if you intend to publish or accept contributions.

contributions & issues
- open issues or PRs against the repository for feature requests, bug reports, or documentation improvements.

contact
- see repository owner and issues on github for discussion.
