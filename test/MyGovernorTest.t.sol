// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {MyGovernor} from "../src/MyGovernor.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    GovToken govToken;
    TimeLock timelock;
    Box box;

    address public USER = makeAddr("user");
    uint256 public constant INTIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hour
    uint256 public constant VOTING_DELAY = 1; // 1 block --> How many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400; // 1 week

    // WE leave both blank so anyone can propose and execute
    address[] proposers;
    address[] executors;

    // The array of values we need for the proposal, normally is 0
    uint256[] values;
    bytes[] calldatas;
    address[] targets;


    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INTIAL_SUPPLY);    
        
        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();


        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));


        
        
    }


    function testCanUpdateBoxWithoutGovernance() public {
        vm.prank(USER);
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdateBox() public {
        // Arrange the values for the proposal
        uint256 valueToStore = 888;
        string memory description = "store 1 in the box";
        bytes memory encodeFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        
        calldatas.push(encodeFunctionCall);
        values.push(0);
        targets.push(address(box));


        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // view the state:
        //enum ProposalState {
        // Pending, --> 0
        // Active, --> 1
        // Canceled, --> 2
        // Defeated, --> 3
        // Succeeded, --> 4
        // Queued, --> 5
        // Expired, --> 6
        // Executed --> 7
    

        console.log("Proposal state: ", uint256(governor.state(proposalId))); // Should return 0 --> pending state

        // Pass some blocks to see the changes of  the state
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Proposal after voting delay state: ", uint256(governor.state(proposalId))); // Should return 1 --> active state

        // 2. Vote;
        //enum VoteType {
        // Against, --> 0
        // For, --> 1
        // Abstain --> 2

        string memory reason = "I think 888 is better than zero";
        uint8 voteType = 1; //  voteFor
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteType, reason);


        // Pass the voting period to start queuing
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);
        console.log("Proposal after voting period state: ", uint256(governor.state(proposalId))); // Succeeded, --> 4

        // 3. Queue the TX
        // We have to call the queue() function with the same parameters as we proposed, but with the description hashed
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Pass the MIN_DELAY to execute the propose and change the number to 888
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);
        console.log("Proposal after queued (Mindelay) state: ", uint256(governor.state(proposalId))); // queued , --> 5

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);
        console.log("Proposal after queued (Mindelay) state: ", uint256(governor.state(proposalId))); // executed , --> 7


        // Assert we changed the number to 888

        assert(box.getNumber() == valueToStore);
        console.log("Box value: ", box.getNumber());





    }






}