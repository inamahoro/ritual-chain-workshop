// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        mapping(address => bool) hasApproved;
        mapping(address => uint256) aiScores;
        address[] signers;
        mapping(address => bool) isSigner;
        uint256 requiredSignatures;
        uint256 approvalCount;
        bool judged;
        bool winnerProposed;
        address proposedWinner;
        uint256 proposedIndex;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        uint256 signerCount;
        uint256 requiredSignatures;
        uint256 approvalCount;
        bool judged;
        bool winnerProposed;
        address proposedWinner;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event SignerAdded(uint256 indexed id, address indexed signer);
    event SignerRemoved(uint256 indexed id, address indexed signer);
    event WinnerProposed(uint256 indexed id, address indexed winner);
    event WinnerApproved(uint256 indexed id, address indexed signer);
    event WinnerFinalized(uint256 indexed id, address indexed winner);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyAfterReveal(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Reveal phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier onlySigner(uint256 id) {
        require(challenges[id].isSigner[msg.sender], "Not a signer");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        address[] calldata initialSigners,
        uint256 requiredSignatures
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(initialSigners.length > 0, "At least one signer required");
        require(requiredSignatures > 0 && requiredSignatures <= initialSigners.length, "Invalid required signatures");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.requiredSignatures = requiredSignatures;

        uint256 len = initialSigners.length;
        for (uint i = 0; i < len; i++) {
            c.isSigner[initialSigners[i]] = true;
            c.signers.push(initialSigners[i]);
            emit SignerAdded(id, initialSigners[i]);
        }

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealAnswer(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function setAIScores(
        uint256 id,
        address[] calldata participants,
        uint256[] calldata scores
    ) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(!c.judged, "Already judged");
        require(participants.length == scores.length, "Length mismatch");

        uint256 len = participants.length;
        for (uint i = 0; i < len; i++) {
            require(c.hasRevealed[participants[i]], "Participant not revealed");
            c.aiScores[participants[i]] = scores[i];
        }

        c.judged = true;
    }

    function proposeWinner(uint256 id, uint256 winnerIndex) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.judged, "AI must judge first");
        require(winnerIndex < c.answers.length, "Invalid winner index");
        require(!c.winnerProposed, "Winner already proposed");

        c.winnerProposed = true;
        c.proposedWinner = c.participants[winnerIndex];
        c.proposedIndex = winnerIndex;

        emit WinnerProposed(id, c.proposedWinner);
    }

    function approveWinner(uint256 id) external 
        challengeExists(id)
        onlySigner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.winnerProposed, "Winner not proposed");
        require(!c.hasApproved[msg.sender], "Already approved");

        c.hasApproved[msg.sender] = true;
        c.approvalCount++;

        emit WinnerApproved(id, msg.sender);

        if (c.approvalCount >= c.requiredSignatures) {
            c.finalized = true;
            c.winner = c.proposedWinner;
            payable(c.winner).transfer(c.reward);
            emit WinnerFinalized(id, c.winner);
        }
    }

    function addSigner(uint256 id, address newSigner) external 
        challengeExists(id)
        onlyOwner(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(!c.isSigner[newSigner], "Already a signer");

        c.isSigner[newSigner] = true;
        c.signers.push(newSigner);

        emit SignerAdded(id, newSigner);
    }

    function removeSigner(uint256 id, address signerToRemove) external 
        challengeExists(id)
        onlyOwner(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.isSigner[signerToRemove], "Not a signer");
        require(c.signers.length > c.requiredSignatures, "Cannot remove below threshold");

        c.isSigner[signerToRemove] = false;
        
        uint256 len = c.signers.length;
        for (uint i = 0; i < len; i++) {
            if (c.signers[i] == signerToRemove) {
                c.signers[i] = c.signers[len - 1];
                c.signers.pop();
                break;
            }
        }

        emit SignerRemoved(id, signerToRemove);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            signerCount: c.signers.length,
            requiredSignatures: c.requiredSignatures,
            approvalCount: c.approvalCount,
            judged: c.judged,
            winnerProposed: c.winnerProposed,
            proposedWinner: c.proposedWinner
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function getSigners(uint256 id) external view returns (address[] memory) {
        return challenges[id].signers;
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function hasApproved(uint256 id, address signer) external view returns (bool) {
        return challenges[id].hasApproved[signer];
    }

    function isSigner(uint256 id, address signer) external view returns (bool) {
        return challenges[id].isSigner[signer];
    }
}
