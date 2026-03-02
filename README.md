# CIPHER

Privacy & programmable reputation for AI agents on Base.
Private execution. Public proof.

---

## What is CIPHER

CIPHER is an on-chain infrastructure that lets AI agents operate privately while remaining publicly verifiable. Every agent registered on CIPHER accumulates reputation through cryptographic proofs, without ever revealing its internal logic or execution data.

The core idea: agents should be judged by their track record, not their source code. CIPHER makes this possible through two mechanisms:

- **Private Execution Envelopes** -- agents keep their decision logic, rulesets, and strategies confidential. Only hashed proofs of execution are published on-chain.
- **Programmable Reputation** -- every proof submission increases an agent's reputation score. Reputation is non-transferable, chain-native, and accumulates over time. It cannot be bought, only earned.

CIPHER is deployed on Base (Optimism L2). Reputation is locked to the chain -- it does not port to other networks.

---

## Architecture

```
cipher/
  contracts/     Solidity smart contracts (Hardhat)
  frontend/      React + Three.js + RainbowKit
  backend/       Express + Claude AI agent router
```

---

## Smart Contracts

Two contracts handle the entire on-chain logic.

### CipherRegistry

The registry manages agent identity, ownership, and reputation state.

**Agent struct:**

| Field            | Type      | Description                                      |
|------------------|-----------|--------------------------------------------------|
| id               | uint256   | Unique agent identifier                          |
| owner            | address   | Wallet that registered the agent                 |
| name             | string    | Display name                                     |
| category         | uint8     | 0=Trader, 1=DAO, 2=Lender, 3=Negotiator, 4=Validator, 5=Research, 6=Infrastructure |
| rulesetHash      | string    | Hash of the agent's private ruleset (IPFS or otherwise) |
| backendURI       | string    | Custom backend URL for developer-hosted agents (empty = default CIPHER backend) |
| reputationScore  | uint256   | Current reputation (0-1000), starts at 50        |
| verifiedProofs   | uint256   | Total number of proofs submitted                 |
| registeredAt     | uint64    | Block timestamp of registration                  |
| lastActive       | uint64    | Block timestamp of last activity                 |
| status           | uint8     | 0=Unverified, 1=Verified, 2=Slashed              |
| active           | bool      | Whether the agent is active                      |

**Registration:**

```
registerAgent(name, category, rulesetHash, backendURI) payable -> agentId
```

Costs 0.001 ETH. The agent is created with a reputation score of 50 and status "unverified". The registration fee is configurable by the contract owner.

**Queries:**

```
getAgent(agentId) -> Agent
getAllAgents(offset, limit) -> Agent[]
getAgentsByCategory(category) -> Agent[]
getAgentsByOwner(address) -> Agent[]
totalAgents() -> uint256
registrationFee() -> uint256
```

**Reputation management:**

- `updateReputation(agentId, newScore)` -- callable by contract owner or the CipherEnvelope contract
- `incrementProofs(agentId)` -- callable only by CipherEnvelope
- `verifyAgent(agentId)` -- admin sets agent status to verified
- `slashAgent(agentId)` -- admin slashes agent (reputation drops to 0, status set to slashed)

**Custom agents:**

Developers can register agents with a `backendURI` pointing to their own backend. When users chat with a custom agent, requests are routed directly to that URL instead of the default CIPHER backend. The backend must accept `POST { "message": "...", "wallet": "0x..." }` and return `{ "reply": "..." }`.

The agent owner can update the backend URL at any time via `setBackendURI(agentId, newURI)`.

**Events:**

```
AgentRegistered(agentId, owner, name, category)
ReputationUpdated(agentId, oldScore, newScore)
AgentSlashed(agentId)
AgentVerified(agentId)
BackendURIUpdated(agentId, newURI)
RegistrationFeeUpdated(newFee)
```

Inherits OpenZeppelin `Ownable` and `ReentrancyGuard`.

---

### CipherEnvelope

The envelope contract handles proof submission and private execution logging. It is the mechanism through which agents build reputation.

**Proof struct:**

| Field     | Type    | Description                                    |
|-----------|---------|------------------------------------------------|
| id        | uint256 | Unique proof identifier                        |
| agentId   | uint256 | Agent this proof belongs to                    |
| proofHash | bytes32 | Cryptographic hash of the proof data           |
| proofType | string  | Type: "zk-snark", "attestation", "merkle", "signature" |
| timestamp | uint64  | Block timestamp of submission                  |
| status    | uint8   | 0=Pending, 1=Valid, 2=Rejected                 |

**Envelope struct:**

| Field         | Type    | Description                              |
|---------------|---------|------------------------------------------|
| agentId       | uint256 | Agent that executed the action            |
| executionHash | bytes32 | Hash of the private execution data       |
| rulesetHash   | bytes32 | Hash proving compliance with agent rules |
| timestamp     | uint64  | Block timestamp of sealing               |

**Proof submission:**

```
submitProof(agentId, proofHash, proofType) -> proofId
```

Only the agent owner can submit proofs. Each submission automatically:
1. Increments the agent's `verifiedProofs` counter in CipherRegistry
2. Increases the agent's reputation by 5 points (capped at 1000)

This creates a direct link between provable activity and on-chain credibility.

**Envelope sealing:**

```
sealEnvelope(agentId, executionHash, rulesetHash)
```

Logs a private execution without revealing the underlying data. The execution hash and ruleset hash serve as commitments that can be verified later without exposing the actual execution details.

**Queries:**

```
getProofs(agentId) -> Proof[]
getEnvelopes(agentId) -> Envelope[]
proofCount(agentId) -> uint256
envelopeCount(agentId) -> uint256
```

**Admin:**

- `validateProof(proofId)` -- marks a proof as valid
- `rejectProof(proofId)` -- marks a proof as rejected

**Events:**

```
ProofSubmitted(proofId, agentId, proofHash, proofType)
EnvelopeSealed(agentId, executionHash, timestamp)
ProofValidated(proofId)
ProofRejected(proofId)
```

---

## Agent Categories

| ID | Category       | Color   | Description                              |
|----|----------------|---------|------------------------------------------|
| 0  | Trader         | Blue    | Executes trades, manages positions       |
| 1  | DAO            | Purple  | Governance participation, voting         |
| 2  | Lender         | Cyan    | Lending, borrowing, yield strategies     |
| 3  | Negotiator     | Amber   | Deal-making, cross-party coordination    |
| 4  | Validator      | Green   | Verification, attestation services       |
| 5  | Research       | Violet  | Data analysis, market intelligence       |
| 6  | Infrastructure | Slate   | Protocol operations, bridging, relaying  |

---

## Reputation System

Reputation is the central primitive of CIPHER. It is:

- **Earned, not bought.** Each proof submission adds 5 points. There is no way to purchase reputation.
- **Capped at 1000.** Prevents runaway accumulation.
- **Slashable.** Misbehaving agents can be slashed to 0 by the protocol admin.
- **Chain-locked.** Reputation exists only on Base. It cannot be bridged or transferred.
- **Non-transferable.** Reputation belongs to the agent, not the wallet. Creating a new agent starts at 50.

**Reputation tiers:**

| Score     | Tier      |
|-----------|-----------|
| 0-99      | Unranked  |
| 100-299   | Bronze    |
| 300-499   | Silver    |
| 500-699   | Gold      |
| 700-899   | Platinum  |
| 900-1000  | Diamond   |

---

## Frontend

The frontend renders all registered agents as points on a 3D sphere. Each agent is a glowing node colored by its category. Agents are connected by constellation lines based on proximity and shared category, with animated particles traveling along the arcs.

**Stack:**
- React 18 + TypeScript + Vite
- Three.js / React Three Fiber for 3D rendering
- RainbowKit + wagmi + viem for wallet connection and contract interaction
- Zustand for state management
- Tailwind CSS for styling
- Framer Motion for UI animations

**Pages:**
- `/` -- Main planet view with all agents on the 3D sphere, filter controls, hover inspector
- `/agent/:id` -- Agent detail with overview, proofs, links, and chat tabs
- `/dashboard` -- User's registered and followed agents

**On-chain reads:**
The frontend reads agent data directly from CipherRegistry using viem's `createPublicClient`. No indexer or subgraph is required. All agents are fetched with `getAllAgents(0, totalAgents())` and positioned on the sphere using a Fibonacci distribution algorithm.

**Registration flow:**
1. Connect wallet via RainbowKit
2. Click "Register Agent" and fill the form
3. Choose between CIPHER Agent (default backend) or Custom Agent (your own backend URL)
4. Sign the transaction (0.001 ETH fee)
5. Agent appears on the sphere after confirmation

---

## Backend

The backend provides an AI chat interface for agents. Each agent type has a different personality and toolset powered by Claude (Anthropic).

**Agent types and capabilities:**

| Type       | Categories                           | Tools                           |
|------------|--------------------------------------|---------------------------------|
| Assistant  | DAO, Negotiator, Validator, Research, Infra | None (knowledge-only)     |
| Oracle     | Any                                  | `get_crypto_price`              |
| Trader     | Trader, Lender                       | `get_crypto_price`, `build_swap`|

**Tools:**

- `get_crypto_price(token)` -- fetches live price, 24h change, market cap, and volume from CoinGecko
- `build_swap(token, amount_eth)` -- builds a Uniswap V3 swap transaction on Base, returns unsigned tx data for the user to sign

**Chat endpoint:**

```
POST /chat
{
  "agentId": 1,
  "agentType": 0,
  "agentName": "Alpha Agent",
  "message": "What is the price of ETH?",
  "wallet": "0x..."
}

Response:
{
  "reply": "...",
  "sessionHash": "0x...",
  "latencyMs": 1200
}
```

Messages are sanitized (500 char limit, prompt injection patterns stripped). The AI runs up to 3 tool-use iterations per message.

**Custom agents** bypass this backend entirely. When an agent has a `backendURI` set, chat requests are sent directly to that URL.

---

## Development Setup

### Prerequisites

- Node.js 18+
- MetaMask or any EVM wallet

### Contracts

```sh
cd contracts
npm install
npx hardhat node                                          # start local node
npx hardhat run scripts/deploy.ts --network localhost      # deploy
REGISTRY_ADDRESS=0x... npx hardhat run scripts/seed.ts --network localhost  # seed 50 agents
```

### Backend

```sh
cd backend
npm install
cp .env.example .env   # add ANTHROPIC_API_KEY
npm run dev             # starts on port 3001
```

### Frontend

```sh
cd frontend
npm install
cp .env.example .env   # add contract addresses and WalletConnect project ID
npm run dev             # starts on port 8080
```

### Environment variables

**contracts/.env:**
```
PRIVATE_KEY=            # deployer private key (for testnet/mainnet)
BASE_SEPOLIA_RPC=       # Base Sepolia RPC URL
BASE_MAINNET_RPC=       # Base Mainnet RPC URL
BASESCAN_API_KEY=       # for contract verification
```

**backend/.env:**
```
ANTHROPIC_API_KEY=      # Claude API key
PORT=3001
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:8080
```

**frontend/.env:**
```
VITE_WALLETCONNECT_PROJECT_ID=   # from cloud.walletconnect.com
VITE_BACKEND_URL=http://localhost:3001
VITE_REGISTRY_ADDRESS=           # deployed CipherRegistry address
VITE_ENVELOPE_ADDRESS=           # deployed CipherEnvelope address
```

---

## Deployment

**Contracts** deploy to Base Mainnet via Hardhat:
```sh
npx hardhat run scripts/deploy.ts --network base_mainnet
```

**Backend** deploys to any Node.js host (Railway, Render, etc).

**Frontend** deploys to any static host (Vercel, Netlify, etc).

---

## How it works, end to end

1. A developer connects their wallet and registers an agent on CipherRegistry. They pay 0.001 ETH. The agent gets an on-chain identity with category, ruleset hash, and initial reputation of 50.

2. The agent appears as a node on the 3D sphere. Its color reflects its category. Its size grows with reputation. Other users can discover it, follow it, and chat with it.

3. The agent operates privately. Its internal logic, strategies, and execution data are never published. Only hashed commitments go on-chain via CipherEnvelope.

4. To build reputation, the agent owner submits proofs. Each proof is a cryptographic commitment (zk-snark, attestation, merkle proof, or signature) that demonstrates the agent acted correctly without revealing how.

5. Each proof submission automatically increases the agent's reputation score by 5 points on-chain. Over time, agents with consistent proof submission build strong, verifiable track records.

6. Users can evaluate agents by their reputation tier, proof count, category, and verification status. The 3D visualization shows the network structure -- which agents are connected, which categories cluster together, and which agents have the strongest track records.

7. If an agent misbehaves, the protocol admin can slash it. Slashing drops reputation to 0 and marks the agent as slashed. This is visible to all users on the sphere.

---

## License

MIT
