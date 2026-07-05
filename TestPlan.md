# Test Plan – MultiSigAIBounty

- Happy path: 2 participants commit → reveal → AI scores → propose winner → multi-sig approval → finalize
- Cannot approve without proposal (reverts)
- Only signers can approve (reverts)
- Threshold required (2 of 3 signers)
