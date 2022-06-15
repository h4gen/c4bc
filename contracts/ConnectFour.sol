pragma solidity ^0.8.7;
/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

pragma solidity ^0.8.7;

contract ConnectFourV1 is ReentrancyGuard{
	/// ERRORS ///
	error InvalidMove();
	error Unauthorized();
	error GameFinished();
	error InvalidStake();
	error InvalidRewards();

	/// EVENTS ///
	event GameStarted(uint256 gameId);
	event MovePerformed(uint256 gameId, uint256 moveId, uint8 col, Color color);
	event GameWon(uint256 gameId, Color color);
	event GameDraw(uint256 gameId);
	event StakeRed(address addr, uint256 value, Color color, uint256 totalAmount);
	event StakeBlue(address addr, uint256 value, Color color, uint256 totalAmount);
	event RewardsCalculated(uint256 gameId, uint256 winColorAmount, uint256 rewardAmount, uint256 treasuryAmt, Color color);
	event Claim(address sender, uint256 epoch, uint256 addedReward);

	struct Game {
		uint64 height;
		uint64[2] board;
		uint8 moves;
		bool finished;
		uint256 redAmount;
		uint256 blueAmount;
		uint256 totalAmount;
		uint256 winColorAmount;
		uint256 rewardAmount;
	}

    enum Color {
        Red,
        Blue
    }

	struct UserRound {
        Color color;
        uint256 amount;
		uint256 last_move;
		bool exists;  // default false
        bool claimed; // default false
    }

	mapping(uint256 => mapping(address => UserRound)) public ledger;
	mapping(uint256 => Game) public games;
	mapping(address => uint256[]) public userStakeGames;

	bool public gameActive = false;
	address public owner;
	uint256[7] internal columnVotes = [0, 0, 0, 0, 0, 0, 0]; 
	uint64 internal constant topColumn = 283691315109952;
	uint64 internal constant maxHeight = 418861572486;
	uint8 internal constant gameFee = 1;
	uint256 internal treasuryAmount;
	uint256 public globalGameId = 0;
	uint256 public globalMoveId = 2;
	uint256 internal minStakeAmount = 10**14;
	uint256 internal blockDelta = 5;
	uint256 internal moveStartBlockNr;
	uint256 internal roundAmountRed;
	uint256 internal roundAmountYello;

	// Checks whether next move should be triggered.
	modifier checkGameTick {
		if ((block.number - moveStartBlockNr) <= blockDelta){
			_;
		} else {
			_;
			_executeMove();
		}
	}

	// Checks that caller is owner of contract.
	modifier onlyOwner {
		require(msg.sender == owner, "Not authorized.");
		_;
	}

	// Checks that game is not paused.
	modifier activeGame {
		require(gameActive, "Game not running.");
		_;
	}

	// Checks that caller is no contract
	modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

	constructor() {
		moveStartBlockNr = block.number;
			Game memory game = Game({
			height: uint64(0),
			board: [uint64(0), uint64(0)],
			moves: 0,
			finished: false,
			redAmount: 0,
			blueAmount: 0,
			totalAmount: 0,
			winColorAmount: 0,
			rewardAmount: 0
		});

		games[globalGameId] = game;
		gameActive = true;
		owner = msg.sender;
	}

	function transferOwnership (address newOwner) public onlyOwner {
		require(newOwner != address(0), 'Cannot be NULL.');
		owner = newOwner;
	}

	function pause() public onlyOwner {
		gameActive = false;
	}

	function unpause() public onlyOwner {
		gameActive = true;
	}

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

	function _executeMove() internal {
		// Load game state
		Game storage game = games[globalGameId];
		// Get column with highest vote for current column
		uint8 col = _getMaxVoteCol();
		if (game.finished) revert GameFinished();
		// Set bit on bitboard for new chip of color
		game.board[game.moves & 1] ^= uint64(1) << ((game.height >> 6*col) & 63);
		// Check if this would be a valid move, revert otherwise.
		if ((game.board[game.moves & 1] & topColumn) != 0) revert InvalidMove();
		// Increment height bit range
		game.height += uint64(1) << 6*col;
		emit MovePerformed(globalGameId, globalMoveId,col, Color(game.moves & 1));
		// Check if this was a winning move
		bool color_wins = _checkColorWin(globalGameId, game.moves & 1);
		// WINNING MOVE
		if (color_wins) {
			game.finished = true;
			emit GameWon(globalGameId, Color(game.moves & 1));
			_calculateRewards(globalGameId);
			_startNewRound();
		// DRAW
		} else if (game.height == maxHeight) {
			emit GameDraw(globalGameId);
			_startNewRound();
		// CONTINUE
		} else {
			moveStartBlockNr = block.number;
			columnVotes = [0, 0, 0, 0, 0, 0, 0]; 
			game.moves++;
			globalMoveId++;
		}
	}

	function _startNewRound() internal {
			Game memory newGame = Game({
				height: uint64(0),
				board: [uint64(0), uint64(0)],
				moves: 0,
				finished: false,
				redAmount: 0,
				blueAmount: 0,
				totalAmount: 0,
				winColorAmount: 0,
				rewardAmount: 0
			});
			games[++globalGameId] = newGame;
			moveStartBlockNr = block.number;
			emit GameStarted(globalGameId);
	}

	function _checkColorWin(uint256 gameId, uint8 side) public view returns (bool) {
		uint64 board = games[gameId].board[side];
		uint8[4] memory directions = [6, 8, 7, 1];
		uint64 bb;
		unchecked {
			for (uint8 i = 0; i < 4; i++) {
				bb = board & (board >> directions[i]);
				if ((bb & (bb >> (directions[i] << 1))) != 0) return true;
			}
		}
		return false;
	}

	function getBoards(uint256 gameId) public view returns (uint64) {
		Game memory game = games[gameId];
		return game.board[0];
	}

	function getValidMoves(uint256 gameId) public view returns (bool[7] memory){
		Game memory game = games[gameId];
		bool[7] memory moves;
		for(uint col = 0; col <= 6; col++) {  
			if (topColumn & (1 << ((game.height >> 6*col) & 63)) == 0){
				moves[col] = true;
			} else {
				moves[col] = false;
			}
		}
		return moves;
	}

	function getFillLevels(uint256 gameId) public view returns (uint64[7] memory){
		Game memory game = games[gameId];
		uint64[7] memory levels;
		for(uint col = 0; col <= 6; col++) {  
			levels[col] = (game.height >> 6*col) & 63;
		}
		return levels;
	}

	function stake(uint256 gameId, Color color) 
	public 
	payable 
	activeGame 
	notContract
	checkGameTick {
		UserRound storage userRound = ledger[gameId][msg.sender];
		require(msg.value >= minStakeAmount, "Stake amount too smol.");
		require(globalGameId <= gameId, "You tried to stake a finised round.");
		if (userRound.amount > 0){
			require(userRound.color == color, "You already staked another color this round.");
		} else {
			Game storage game = games[gameId];
			userRound.color = color;
			userRound.amount += msg.value;
			userStakeGames[msg.sender].push(gameId);
			if (color == Color.Red){
				game.redAmount += msg.value;
				game.totalAmount += msg.value;
				emit StakeRed(msg.sender, msg.value, color, game.totalAmount);
			} else if (color == Color.Blue){
				game.blueAmount += msg.value;
				game.totalAmount += msg.value;
				emit StakeBlue(msg.sender, msg.value, color, game.totalAmount);
			} else {
				revert InvalidStake();
			}
		}
	}

	function vote(uint256 gameId, uint8 col) public activeGame notContract checkGameTick {
		Game storage game = games[gameId];
		require(!game.finished, "You voted for a finished game.");
		UserRound memory userRound = ledger[gameId][msg.sender];
		if (userRound.amount > 0){
			require(userRound.last_move < globalMoveId, "Alreade placed a vote for this move.");
			require(uint(userRound.color) == globalMoveId%2, "You are not voting for the color you've staked.");
			require((userRound.last_move & 1) == (globalMoveId & 1), 'You already voted for the other color this round.');
		}
		userRound.last_move = globalMoveId;
		columnVotes[col] += userRound.amount + (minStakeAmount >> 1);
	}

	function _getMaxVoteCol() internal view returns (uint8){
		uint256 biggestVote = columnVotes[0];
		uint8 biggestVoteCol = 0;
		for(uint8 col = 1; col <= 6; col++) {  
			if (columnVotes[col] > biggestVote){
				biggestVote = columnVotes[col];
				biggestVoteCol = col;
			}
		}
		return biggestVoteCol;
	}

	function getColVotes() public view returns (uint256[7] memory){
		return columnVotes;
	}

	function claimable(uint256 gameId, address user) public view returns (bool) {
		UserRound memory userRound = ledger[gameId][user];
		Game memory game = games[gameId];
		if (!game.finished) {
			return false;
		} 
		return 
			(userRound.color == Color(game.moves & 1)) && 
			(userRound.amount > 0)
		;
	}

	function refundable(uint256 gameId, address user) public view returns (bool) {
		UserRound memory userRound = ledger[gameId][user];
		Game memory game = games[gameId];
		if (game.finished) {
			return false;
		} 
		return 
			(!game.finished) && 
			(game.moves == 41) &&
			(userRound.amount != 0)
		;
	}

	function _calculateRewards(uint256 gameId) internal {
        require(games[gameId].winColorAmount == 0 && games[gameId].rewardAmount == 0, "Rewards calculated");
        Game storage game = games[gameId];
        uint256 winColorAmount;
        uint256 treasuryAmt;
        uint256 rewardAmount;
        // Red wins
        if ((game.moves & 1) == uint8(Color.Red)) {
            winColorAmount = game.redAmount;
            treasuryAmt = (game.totalAmount * gameFee) / 100;
            rewardAmount = game.totalAmount - treasuryAmt;
			emit RewardsCalculated(gameId, winColorAmount, rewardAmount, treasuryAmt, Color.Red);
        }
        // Blue wins
        if ((game.moves & 1) == uint8(Color.Blue)) {
			winColorAmount = game.blueAmount;
			treasuryAmt = (game.totalAmount * gameFee) / 100;
			rewardAmount = game.totalAmount - treasuryAmt;
			emit RewardsCalculated(gameId, winColorAmount, rewardAmount, treasuryAmt, Color.Blue);
        }
        // House wins
        else {
			revert InvalidRewards();
        }
        game.winColorAmount = winColorAmount;
        game.rewardAmount = rewardAmount;
        // Add to treasury
        treasuryAmount += treasuryAmt;
    }

	function claim(uint256[] calldata gameIds) external nonReentrant notContract {
        uint256 reward; // Initializes reward

        for (uint256 i = 0; i < gameIds.length; i++) {
            require(gameIds[i] < globalGameId, "Round has not started.");
            require(games[gameIds[i]].finished, "Round has not ended or is a draw.");

            uint256 addedReward = 0;

            // Round valid, claim rewards
            if (games[gameIds[i]].finished) {
                // require(claimable(gameIds[i], msg.sender), "Not eligible for claim");
                Game memory game = games[gameIds[i]];
                addedReward = (ledger[gameIds[i]][msg.sender].amount * game.rewardAmount) / game.winColorAmount;
            }
            // Round invalid, refund bet amount
            else {
                require(refundable(gameIds[i], msg.sender), "Not eligible for refund");
                addedReward = ledger[gameIds[i]][msg.sender].amount;
            }

            ledger[gameIds[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, gameIds[i], addedReward);
        }

        if (reward > 0) {
            _safeTransfer(address(msg.sender), reward);
        }
    }

	function _safeTransfer(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: BNB_TRANSFER_FAILED");
    }
}