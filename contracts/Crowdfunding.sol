// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);

    function burn(uint256 value) external returns (bool);
}

contract Crowdfunding {
    address public creator;
    address public beneficiary; // The address to transfer funds to
    uint public goalAmount;
    uint public endTime;
    mapping(address => uint) public contributions;
    address[] public contributors;
    mapping(address => bool) public isTokenDistributed;
    bool public isFundingComplete;
    bool public isGoalReached;

    IERC20 public tokenContract;

    address payable gnosisSafe; // The address of the Gnosis Safe
    address[] public owners; // List of Safe owners

    event SafeCreated(address indexed safe);

    event ContributionReceived(address contributor, uint amount);
    event TokensDistributed(address distributor, uint amount);
    event FundingComplete(bool reachedGoal, uint totalAmount);
    event FundsTransferred(address to, uint amount);

    constructor(
        address _tokenContract,
        address _beneficiary,
        uint _goalAmount,
        uint _durationDays,
        address[] memory _owners
    ) {
        creator = msg.sender;
        beneficiary = _beneficiary;
        goalAmount = _goalAmount * 1 ether;
        endTime = block.timestamp + _durationDays * 1 days;
        tokenContract = IERC20(_tokenContract);

        owners = _owners;
        createGnosisSafe();
    }

    modifier onlySafe() {
        require(
            msg.sender == gnosisSafe,
            "Only the Gnosis Safe can call this function"
        );
        _;
    }

    modifier onlyAfterTokenBurn(address contributor) {
        require(
            tokenContract.burn(contributions[contributor]),
            "Token burn failed"
        );
        _;
    }

    modifier onlyBeforeEndTime() {
        require(block.timestamp < endTime, "Funding period has ended");
        _;
    }

    modifier onlyAfterEndTime() {
        require(block.timestamp >= endTime, "Funding period has not ended yet");
        _;
    }

    function createGnosisSafe() internal {
        gnosisSafe = payable(address(new GnosisSafeProxy(msg.sender)));
        emit SafeCreated(gnosisSafe);

        // Initialize Safe's owners
        GnosisSafe(gnosisSafe).setup(
            owners,
            2,
            address(0),
            bytes(""),
            address(0),
            address(0),
            0,
            payable(address(0))
        );
    }

    function contribute() public payable onlyBeforeEndTime {
        require(!isFundingComplete, "Funding is already complete");
        contributors.push(msg.sender);
        contributions[msg.sender] += msg.value;
        emit ContributionReceived(msg.sender, msg.value);
    }

    function distributeTokens() external onlyAfterEndTime onlySafe {
        require(isFundingComplete, "Funding is not complete yet");
        require(
            isGoalReached,
            "Goal was not reached, tokens cannot be distributed"
        );

        for (uint i = 0; i < contributors.length; i++) {
            require(
                !isTokenDistributed[contributors[i]],
                "Tokens already distributed to this address"
            );
            uint totalContributions = contributions[contributors[i]];
            require(totalContributions > 0, "You have no contributions");

            isTokenDistributed[contributors[i]] = true;
            require(
                tokenContract.transfer(contributors[i], totalContributions),
                "Token transfer failed"
            );

            emit TokensDistributed(contributors[i], totalContributions);
        }
    }

    function checkFundingStatus() external onlyAfterEndTime {
        require(!isFundingComplete, "Funding status has already been checked");

        uint totalAmount = address(this).balance;

        if (totalAmount >= goalAmount) {
            isGoalReached = true;
            // Transfer funds to the creator
            payable(creator).transfer(totalAmount);
        }

        isFundingComplete = true;
        emit FundingComplete(isGoalReached, totalAmount);
    }

    // Allow contributors to withdraw their contributions if the goal was not reached
    function withdrawContribution()
        external
        onlyAfterEndTime
        onlyAfterTokenBurn(msg.sender)
    {
        require(
            isFundingComplete && !isGoalReached,
            "Funding is not complete or goal was reached"
        );
        uint contributionAmount = contributions[msg.sender];
        require(
            contributionAmount > 0,
            "You have no contributions to withdraw"
        );

        contributions[msg.sender] = 0;
        payable(msg.sender).transfer(contributionAmount);
    }

    function transferTokensToBeneficiary() external onlySafe {
        require(
            isFundingComplete && isGoalReached,
            "Funding is not complete or goal was not reached"
        );

        uint totalTokenAmount = address(this).balance; // Calculate the total token amount to transfer

        // Transfer tokens to the beneficiary
        require(
            tokenContract.transfer(beneficiary, totalTokenAmount),
            "Token transfer failed"
        );
    }

    // Fallback function to receive ether
    receive() external payable onlyBeforeEndTime {
        contribute();
    }
}
