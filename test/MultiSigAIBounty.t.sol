// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/MultiSigAIBounty.sol";

contract MultiSigAIBountyTest is Test {
    MultiSigAIBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address signer1 = address(0x4);
    address signer2 = address(0x5);
    address signer3 = address(0x6);
    uint256 challengeId;
    bytes32 aliceCommitment;
    bytes32 bobCommitment;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";
    uint256 reward = 1 ether;

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        bounty = new MultiSigAIBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days, signers, 2);
        challengeId = 0;
        vm.stopPrank();
        aliceCommitment = keccak256(abi.encodePacked(aliceAnswer, aliceSalt, alice, challengeId));
        bobCommitment = keccak256(abi.encodePacked(bobAnswer, bobSalt, bob, challengeId));
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.submitCommitment(challengeId, bobCommitment);
        vm.stopPrank();

        // Move to reveal phase
        vm.warp(block.timestamp + 1 days + 1);

        // Reveal
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAnswer(challengeId, bobAnswer, bobSalt);
        vm.stopPrank();

        // Move to after reveal phase
        vm.warp(block.timestamp + 2 days + 1);

        // Set AI scores
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 85;
        scores[1] = 90;

        vm.startPrank(owner);
        bounty.setAIScores(challengeId, participants, scores);
        vm.stopPrank();

        // Propose winner
        vm.startPrank(owner);
        bounty.proposeWinner(challengeId, 1);
        vm.stopPrank();

        // Approve winner (2 of 3 signers needed)
        vm.startPrank(signer1);
        bounty.approveWinner(challengeId);
        vm.stopPrank();

        vm.startPrank(signer2);
        bounty.approveWinner(challengeId);
        vm.stopPrank();

        MultiSigAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + reward);
    }

    function testCannotApproveWithoutProposal() public {
        // First commit and reveal
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);

        // Set AI scores
        address[] memory participants = new address[](1);
        participants[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.startPrank(owner);
        bounty.setAIScores(challengeId, participants, scores);
        vm.stopPrank();

        // Try to approve without proposal
        vm.startPrank(signer1);
        vm.expectRevert("Winner not proposed");
        bounty.approveWinner(challengeId);
        vm.stopPrank();
    }

    function testOnlySignerCanApprove() public {
        // Commit and reveal
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);

        // Set AI scores
        address[] memory participants = new address[](1);
        participants[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.startPrank(owner);
        bounty.setAIScores(challengeId, participants, scores);
        vm.stopPrank();

        // Propose winner
        vm.startPrank(owner);
        bounty.proposeWinner(challengeId, 0);
        vm.stopPrank();

        // Non-signer tries to approve
        vm.startPrank(alice);
        vm.expectRevert("Not a signer");
        bounty.approveWinner(challengeId);
        vm.stopPrank();
    }

    function testThresholdRequired() public {
        // Commit and reveal
        vm.startPrank(alice);
        bounty.submitCommitment(challengeId, aliceCommitment);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(alice);
        bounty.revealAnswer(challengeId, aliceAnswer, aliceSalt);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);

        // Set AI scores
        address[] memory participants = new address[](1);
        participants[0] = alice;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.startPrank(owner);
        bounty.setAIScores(challengeId, participants, scores);
        vm.stopPrank();

        // Propose winner
        vm.startPrank(owner);
        bounty.proposeWinner(challengeId, 0);
        vm.stopPrank();

        // Only 1 approval (threshold is 2) - should not finalize
        vm.startPrank(signer1);
        bounty.approveWinner(challengeId);
        vm.stopPrank();

        MultiSigAIBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertFalse(info.finalized);
        assertEq(info.approvalCount, 1);
    }
}
