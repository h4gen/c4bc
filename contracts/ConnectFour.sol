pragma solidity ^0.8.10;

contract ConnectFourV1 {
	/// ERRORS ///
	error InvalidMove();
	error Unauthorized();
	error GameFinished();

	/// EVENTS ///
	event GameStarted(uint256 gameId);
	event MovePerformed(uint256 gameId, uint256 moveId, uint8 col, Color color);
	event GameWon(uint256 gameId, Color color);
	event GameDraw(uint256 gameId);
	event Stake(address addr, uint256 value, Color color);

	struct Game {
		uint64 height;
		uint64[2] board;
		uint8 moves;
		bool finished;
	}

	bool roundActive = false;
	uint256[7] internal columnVotes = [0, 0, 0, 0, 0, 0, 0]; 

    enum Color {
        Red,
        Yellow
    }

	struct UserRound {
        Color color;
        uint256 amount;
		uint256 last_move;
		bool exists;
        bool claimed; // default false
    }

    mapping(uint256 => mapping(address => UserRound)) public ledger;
	mapping(uint256 => Game) public games;
    mapping(address => uint256[]) public userGames;

	uint64 internal constant topColumn = 283691315109952;
	uint256 public globalGameId = 0;
	uint256 public globalMoveId = 2;
	uint256 internal minStakeAmount = 10**14;
	uint256 internal blockDelta = 5;
	uint256 internal moveStartBlockNr;
	uint256 internal roundAmountRed;
	uint256 internal roundAmountYello;

	modifier checkGameTick {
		if ((block.number - moveStartBlockNr) <= blockDelta){
			_;
		} else {
			_;
			_executeMove();
		}
	}

	constructor() {
		moveStartBlockNr = block.number;
			Game memory game = Game({
			height: uint64(0),
			board: [uint64(0), uint64(0)],
			moves: 0,
			finished: false
		});

		games[globalGameId] = game;
	}

	function _executeMove() internal {
		Game storage game = games[globalGameId];
		moveStartBlockNr = block.number;
		uint8 col = _getMaxVoteCol();
		if (game.finished) revert GameFinished();
		game.board[game.moves & 1] ^= uint64(1) << ((game.height >> 6*col) & 63);
		game.height += uint64(1) << 6*col;
		if ((game.board[game.moves & 1] & topColumn) != 0) revert InvalidMove();
		emit MovePerformed(globalGameId, globalMoveId,col, Color(game.moves & 1));
		bool color_wins = _checkColorWin(globalGameId, game.moves & 1);
		if (color_wins) {
			game.finished = true;
			emit GameWon(globalGameId, Color(game.moves & 1));
			_startNewRound();
		} else if (game.height == 418861572486) {
			emit GameDraw(globalGameId);
			_startNewRound();
		} else {
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
				finished: false
			});
			games[++globalGameId] = newGame;
			emit GameStarted(globalGameId);
	}

	function _checkColorWin(uint256 gameId, uint8 side) public view returns (bool) {
		uint64 board = games[gameId].board[side];
		uint8[4] memory directions = [1, 7, 6, 8];
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

	function stake(uint256 gameId, Color color) public payable checkGameTick {
		UserRound storage userRound = ledger[gameId][msg.sender];
		require(msg.value >= minStakeAmount, "Stake amount too smol.");
		require(globalGameId <= gameId, "You tried to stake a finised round.");
		if (userRound.amount > 0){
			require(userRound.color == color, "You already staked another color this round.");
		} else {
			userRound.color = color;
			userRound.amount += msg.value;
			userGames[msg.sender].push(gameId);
			emit Stake(msg.sender, msg.value, color);
		}
	}

	function vote(uint256 gameId, uint8 col) public checkGameTick {
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
}