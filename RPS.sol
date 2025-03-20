// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract RPS {
    IERC20 public token;  // ERC20 token used for payments (e.g., WETH)
    uint public reward = 0;
    uint public commitDeadline;
    uint public revealDeadline;
    address[] public players;
    
    mapping(address => bytes32) public playerCommit;
    mapping(address => uint) public playerChoice;
    mapping(address => bool) public hasRevealed;
    
    bool public gameStarted = false;
    
    modifier onlyPlayers() {
        require(msg.sender == players[0] || msg.sender == players[1], "Not a player");
        _;
    }

    event GameStarted(address player1, address player2);
    event MoveCommitted(address player);
    event MoveRevealed(address player, uint choice);
    event WinnerPaid(address winner, uint amount);
    event FundsWithdrawn(address by, uint amount);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function addPlayer(bytes32 moveCommit) public {
        require(players.length < 2, "Game full");
        require(playerCommit[msg.sender] == 0, "Already committed");

        players.push(msg.sender);
        playerCommit[msg.sender] = moveCommit;

        if (players.length == 2) {
            commitDeadline = block.timestamp + 5 minutes;  // Players must reveal within 5 minutes
            revealDeadline = commitDeadline + 5 minutes;
            gameStarted = true;
            emit GameStarted(players[0], players[1]);
        }

        emit MoveCommitted(msg.sender);
    }

    function depositFunds() public onlyPlayers {
        require(token.allowance(msg.sender, address(this)) >= 0.000001 ether, "Insufficient allowance");
        require(token.transferFrom(msg.sender, address(this), 0.000001 ether), "Transfer failed");
        reward += 0.000001 ether;
    }

    function revealMove(uint choice, string memory secret) public onlyPlayers {
        require(block.timestamp <= revealDeadline, "Reveal time expired");
        require(hasRevealed[msg.sender] == false, "Already revealed");
        require(playerCommit[msg.sender] == keccak256(abi.encodePacked(choice, secret)), "Invalid commitment");

        playerChoice[msg.sender] = choice;
        hasRevealed[msg.sender] = true;

        emit MoveRevealed(msg.sender, choice);

        if (hasRevealed[players[0]] && hasRevealed[players[1]]) {
            _checkWinnerAndPay();
        }
    }

    function _checkWinnerAndPay() private {
        uint p0Choice = playerChoice[players[0]];
        uint p1Choice = playerChoice[players[1]];
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);

        if ((p0Choice + 1) % 3 == p1Choice) {
            token.transfer(account1, reward);
            emit WinnerPaid(account1, reward);
        } 
        else if ((p1Choice + 1) % 3 == p0Choice) {
            token.transfer(account0, reward);
            emit WinnerPaid(account0, reward);
        } 
        else {
            token.transfer(account0, reward / 2);
            token.transfer(account1, reward / 2);
            emit WinnerPaid(account0, reward / 2);
            emit WinnerPaid(account1, reward / 2);
        }

        // Reset game state
        delete players;
        reward = 0;
        gameStarted = false;
    }

    function claimTimeoutWin() public onlyPlayers {
        require(block.timestamp > revealDeadline, "Not yet timeout");

        address winner;
        if (hasRevealed[players[0]] && !hasRevealed[players[1]]) {
            winner = players[0];
        } else if (!hasRevealed[players[0]] && hasRevealed[players[1]]) {
            winner = players[1];
        } else {
            revert("Both players failed to reveal");
        }

        token.transfer(payable(winner), reward);
        emit WinnerPaid(winner, reward);

        // Reset game state
        delete players;
        reward = 0;
        gameStarted = false;
    }

    function withdrawFunds() public {
        require(block.timestamp > revealDeadline + 5 minutes, "Cannot withdraw yet");
        require(!hasRevealed[players[0]] && !hasRevealed[players[1]], "Players revealed");

        token.transfer(msg.sender, reward);
        emit FundsWithdrawn(msg.sender, reward);

        // Reset game state
        delete players;
        reward = 0;
        gameStarted = false;
    }
}

