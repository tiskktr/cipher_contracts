// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CipherRegistry is Ownable, ReentrancyGuard {

    struct Agent {
        uint256 id;
        address owner;
        string name;
        uint8 category;         // 0=trader, 1=dao, 2=lender, 3=negotiator, 4=validator, 5=research, 6=infra
        string rulesetHash;     // IPFS hash of private ruleset
        string backendURI;      // custom backend URL (empty = use default CIPHER backend)
        uint256 reputationScore;
        uint256 verifiedProofs;
        uint64 registeredAt;
        uint64 lastActive;
        uint8 status;           // 0=unverified, 1=verified, 2=slashed
        bool active;
    }

    uint256 private _nextAgentId;
    uint256 public registrationFee;
    address public envelopeContract;

    mapping(uint256 => Agent) public agents;
    uint256[] private _agentIds;
    mapping(address => uint256[]) private _ownerAgents;
    mapping(uint8 => uint256[]) private _categoryAgents;

    event AgentRegistered(uint256 indexed agentId, address indexed owner, string name, uint8 category);
    event ReputationUpdated(uint256 indexed agentId, uint256 oldScore, uint256 newScore);
    event AgentSlashed(uint256 indexed agentId);
    event AgentVerified(uint256 indexed agentId);
    event BackendURIUpdated(uint256 indexed agentId, string newURI);
    event RegistrationFeeUpdated(uint256 newFee);

    constructor(address initialOwner) Ownable(initialOwner) {
        _nextAgentId = 1;
        registrationFee = 0.001 ether;
    }

    modifier onlyEnvelope() {
        require(msg.sender == envelopeContract, "CipherRegistry: caller is not envelope");
        _;
    }

    // ── Registration ──────────────────────────────────────────────

    function registerAgent(
        string calldata name,
        uint8 category,
        string calldata rulesetHash,
        string calldata backendURI
    ) external payable nonReentrant returns (uint256) {
        require(bytes(name).length > 0, "CipherRegistry: empty name");
        require(category <= 6, "CipherRegistry: invalid category");
        require(msg.value >= registrationFee, "CipherRegistry: insufficient fee");

        uint256 agentId = _nextAgentId++;

        agents[agentId] = Agent({
            id: agentId,
            owner: msg.sender,
            name: name,
            category: category,
            rulesetHash: rulesetHash,
            backendURI: backendURI,
            reputationScore: 50,
            verifiedProofs: 0,
            registeredAt: uint64(block.timestamp),
            lastActive: uint64(block.timestamp),
            status: 0,
            active: true
        });

        _agentIds.push(agentId);
        _ownerAgents[msg.sender].push(agentId);
        _categoryAgents[category].push(agentId);

        emit AgentRegistered(agentId, msg.sender, name, category);
        return agentId;
    }

    // ── Update backend URI (agent owner only) ─────────────────────

    function setBackendURI(uint256 agentId, string calldata newURI) external {
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");
        require(msg.sender == agents[agentId].owner, "CipherRegistry: not agent owner");
        agents[agentId].backendURI = newURI;
        emit BackendURIUpdated(agentId, newURI);
    }

    // ── Queries ───────────────────────────────────────────────────

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");
        return agents[agentId];
    }

    function getAllAgents(uint256 offset, uint256 limit) external view returns (Agent[] memory) {
        uint256 total = _agentIds.length;
        if (offset >= total) return new Agent[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;

        Agent[] memory result = new Agent[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = agents[_agentIds[offset + i]];
        }
        return result;
    }

    function getAgentsByCategory(uint8 category) external view returns (Agent[] memory) {
        uint256[] storage ids = _categoryAgents[category];
        Agent[] memory result = new Agent[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = agents[ids[i]];
        }
        return result;
    }

    function getAgentsByOwner(address ownerAddr) external view returns (Agent[] memory) {
        uint256[] storage ids = _ownerAgents[ownerAddr];
        Agent[] memory result = new Agent[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = agents[ids[i]];
        }
        return result;
    }

    function totalAgents() external view returns (uint256) {
        return _agentIds.length;
    }

    // ── Reputation (called by CipherEnvelope or owner) ────────────

    function updateReputation(uint256 agentId, uint256 newScore) external {
        require(
            msg.sender == owner() || msg.sender == envelopeContract,
            "CipherRegistry: not authorized"
        );
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");

        uint256 oldScore = agents[agentId].reputationScore;
        agents[agentId].reputationScore = newScore;
        agents[agentId].lastActive = uint64(block.timestamp);

        emit ReputationUpdated(agentId, oldScore, newScore);
    }

    function incrementProofs(uint256 agentId) external onlyEnvelope {
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");
        agents[agentId].verifiedProofs++;
        agents[agentId].lastActive = uint64(block.timestamp);
    }

    // ── Admin ─────────────────────────────────────────────────────

    function verifyAgent(uint256 agentId) external onlyOwner {
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");
        agents[agentId].status = 1;
        emit AgentVerified(agentId);
    }

    function slashAgent(uint256 agentId) external onlyOwner {
        require(agents[agentId].registeredAt > 0, "CipherRegistry: agent not found");
        agents[agentId].status = 2;
        agents[agentId].reputationScore = 0;
        emit AgentSlashed(agentId);
    }

    function setRegistrationFee(uint256 fee) external onlyOwner {
        registrationFee = fee;
        emit RegistrationFeeUpdated(fee);
    }

    function setEnvelopeContract(address envelope) external onlyOwner {
        envelopeContract = envelope;
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = owner().call{value: address(this).balance}("");
        require(ok, "CipherRegistry: withdraw failed");
    }
}
