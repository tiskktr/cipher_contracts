// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICipherRegistry {
    function agents(uint256 agentId) external view returns (
        uint256 id,
        address owner,
        string memory name,
        uint8 category,
        string memory rulesetHash,
        string memory backendURI,
        uint256 reputationScore,
        uint256 verifiedProofs,
        uint64 registeredAt,
        uint64 lastActive,
        uint8 status,
        bool active
    );
    function updateReputation(uint256 agentId, uint256 newScore) external;
    function incrementProofs(uint256 agentId) external;
}

contract CipherEnvelope is Ownable, ReentrancyGuard {

    struct Proof {
        uint256 id;
        uint256 agentId;
        bytes32 proofHash;
        string proofType;       // "zk-snark", "attestation", "merkle", "signature"
        uint64 timestamp;
        uint8 status;           // 0=pending, 1=valid, 2=rejected
    }

    struct Envelope {
        uint256 agentId;
        bytes32 executionHash;  // hash of private execution
        bytes32 rulesetHash;    // hash proving ruleset compliance
        uint64 timestamp;
    }

    ICipherRegistry public registry;
    uint256 private _nextProofId;

    mapping(uint256 => Proof) public proofs;
    mapping(uint256 => uint256[]) private _agentProofs;   // agentId => proofIds
    mapping(uint256 => Envelope[]) private _agentEnvelopes; // agentId => envelopes

    uint256 public constant REPUTATION_PER_PROOF = 5;
    uint256 public constant MAX_REPUTATION = 1000;

    event ProofSubmitted(uint256 indexed proofId, uint256 indexed agentId, bytes32 proofHash, string proofType);
    event EnvelopeSealed(uint256 indexed agentId, bytes32 executionHash, uint64 timestamp);
    event ProofValidated(uint256 indexed proofId);
    event ProofRejected(uint256 indexed proofId);

    constructor(address initialOwner, address registryAddress) Ownable(initialOwner) {
        registry = ICipherRegistry(registryAddress);
        _nextProofId = 1;
    }

    // ── Proof Submission ──────────────────────────────────────────

    function submitProof(
        uint256 agentId,
        bytes32 proofHash,
        string calldata proofType
    ) external nonReentrant returns (uint256) {
        // Verify agent exists and caller is the agent owner
        (
            , address agentOwner, , , , , uint256 currentRep, ,
            uint64 registeredAt, , ,
        ) = registry.agents(agentId);
        require(registeredAt > 0, "CipherEnvelope: agent not found");
        require(msg.sender == agentOwner, "CipherEnvelope: not agent owner");

        uint256 proofId = _nextProofId++;

        proofs[proofId] = Proof({
            id: proofId,
            agentId: agentId,
            proofHash: proofHash,
            proofType: proofType,
            timestamp: uint64(block.timestamp),
            status: 0 // pending
        });

        _agentProofs[agentId].push(proofId);

        // Auto-increment verified proofs in registry
        registry.incrementProofs(agentId);

        // Auto-update reputation (+5 per proof, max 1000)
        uint256 newRep = currentRep + REPUTATION_PER_PROOF;
        if (newRep > MAX_REPUTATION) newRep = MAX_REPUTATION;
        registry.updateReputation(agentId, newRep);

        emit ProofSubmitted(proofId, agentId, proofHash, proofType);
        return proofId;
    }

    // ── Envelope Sealing ──────────────────────────────────────────

    function sealEnvelope(
        uint256 agentId,
        bytes32 executionHash,
        bytes32 rulesetHash
    ) external nonReentrant {
        // Verify agent exists and caller is the agent owner
        (, address agentOwner, , , , , , , uint64 registeredAt, , , ) = registry.agents(agentId);
        require(registeredAt > 0, "CipherEnvelope: agent not found");
        require(msg.sender == agentOwner, "CipherEnvelope: not agent owner");

        _agentEnvelopes[agentId].push(Envelope({
            agentId: agentId,
            executionHash: executionHash,
            rulesetHash: rulesetHash,
            timestamp: uint64(block.timestamp)
        }));

        emit EnvelopeSealed(agentId, executionHash, uint64(block.timestamp));
    }

    // ── Queries ───────────────────────────────────────────────────

    function getProofs(uint256 agentId) external view returns (Proof[] memory) {
        uint256[] storage ids = _agentProofs[agentId];
        Proof[] memory result = new Proof[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = proofs[ids[i]];
        }
        return result;
    }

    function getEnvelopes(uint256 agentId) external view returns (Envelope[] memory) {
        return _agentEnvelopes[agentId];
    }

    function proofCount(uint256 agentId) external view returns (uint256) {
        return _agentProofs[agentId].length;
    }

    function envelopeCount(uint256 agentId) external view returns (uint256) {
        return _agentEnvelopes[agentId].length;
    }

    // ── Admin ─────────────────────────────────────────────────────

    function validateProof(uint256 proofId) external onlyOwner {
        require(proofs[proofId].timestamp > 0, "CipherEnvelope: proof not found");
        proofs[proofId].status = 1;
        emit ProofValidated(proofId);
    }

    function rejectProof(uint256 proofId) external onlyOwner {
        require(proofs[proofId].timestamp > 0, "CipherEnvelope: proof not found");
        proofs[proofId].status = 2;
        emit ProofRejected(proofId);
    }

    function setRegistry(address registryAddress) external onlyOwner {
        registry = ICipherRegistry(registryAddress);
    }
}
