// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MysteryChineseChess is Ownable {
    uint24 public constant MAX_GAME_DURATION = 30 * 60 * 1000; // 30 minutes at maximum by default for each player
    // Represent color of piece; use this constant to retrieve players in a game
    uint8 public constant RED = 0;
    uint8 public constant BLACK = 1;

    //? "indexed" keyword should be with address param?
//    event NewRoomCreated(string gameName, address creator);
//    event NewGameStarted(string gameName, address player1, address player2);
    event GameEnded(string gameName, address winner, address loser);

    enum GameStatus {PENDING, STARTED, ENDED}
    enum Piece {
        None,
        General, // king
        Advisor, // guard, assistant
        Elephant, // bishop
        Horse, // knight
        Chariot, // rook, car
        Cannon,
        Soldier // pawn
    }

    struct Room {
        uint256 number; // a.k.a. index
        address[2] players; // should be accessed using the constants 'BLACK', 'RED'
        uint8 hostIndex;
        uint256 stake;
        uint24 gameDuration;
        bool inGame;
        // TODO: may allow audiences to join
    }

    struct Match {
        uint256 id;
        uint256 roomNumber;
//        string name;
        GameStatus gameStatus;
        PlayerPiece[9][10] board;
        address[2] players; // should be accessed using the constants 'BLACK', 'RED'
        uint256 stake;
        uint256 startTimestamp;
        uint256 endTimestamp;
        // TODO: add necessary timestamps & validate actions based on them
    }

    struct PlayerPiece {
        uint8 color; // either RED (0) or BLACK (1)
        Piece piece;
        bool unfolded; // 2 purposes: identify if a piece has moved or not; decide rule of its next move (comply with the rule of which Piece)
    }

    struct Player {
        address playerAddress;
        string playerName;
        uint256 roomNumber; // Store a reference to the room that player is currently in (0 if not in any room)
    }

    struct Position {
        uint8 row;
        uint8 column;
    }

    /* State variables */

    mapping(address => uint256) public playerIndexes; // player's address => player's index
//    mapping(uint256 => uint256) public roomIndexes;
    mapping(uint256 => uint256) public matchIndexes; // game's id => game's index (of 'matches' array)
    /**
     * May use this to understand piece moves sent from client.
     * Initialized & filled with data only once when constructing this contract.
     */
    mapping(string => uint8) internal letterToIndex;

    Player[] public players;
    Room[] public rooms;
    Match[] public matches;
    /**
     * Use this to identify a piece based on its original position.
     * Initialized & filled with data only once when constructing this contract.
     */
    Piece[][] public originalPieces;

//    string public baseURI;
//    uint public totalSupply;

    /**/

    /* Modifiers */

    modifier roomExists(uint32 roomNumber) {
        require(rooms[roomNumber].number != 0, "Room does not exist");
        _;
    }

    modifier matchExists(uint256 matchId) {
        require(matches[matchIndexes[matchId]].id != 0, "The match does not exist");
        _;
    }

    modifier joiningRoom(uint256 roomNumber) {
        require(isPlayer(_msgSender()), string.concat("Unknown player with address ", _msgSender()));
        require(rooms[roomNumber].number != 0, "Room does not exist");

        Room memory _room = rooms[roomNumber];
        Player[2] memory _players = _room.players;

        require(_msgSender() == _players[0] || _msgSender() == _players[1], "You are not participating in this game");
        _;
    }

//    modifier matchExists(uint256 matchId) {
//        require(matches[matchIndexes[matchId]].id != 0, "The match does not exist");
//        _;
//    }

    /**/

    constructor() payable Ownable(_msgSender()) {
        _initialize();
        _initializeOriginalPieces();
    }

    function _initialize() private {
        PlayerPiece[9][10] memory emptyBoard;

        rooms.push(Room(0, [address(0), address(0)], 0, 0, MAX_GAME_DURATION, false));
        matches.push(Match(0, 0, GameStatus.ENDED, emptyBoard, [address(0), address(0)], 0, 0, 0));
        players.push(Player(address(0), "", false));

        letterToIndex['A'] = 0;
        letterToIndex['B'] = 1;
        letterToIndex['C'] = 2;
        letterToIndex['D'] = 3;
        letterToIndex['E'] = 4;
        letterToIndex['F'] = 5;
        letterToIndex['G'] = 6;
        letterToIndex['H'] = 7;
        letterToIndex['I'] = 8;
    }

    function _initializeOriginalPieces() private {
        originalPieces[0][0] = Piece.Chariot;
        originalPieces[0][8] = Piece.Chariot;
        originalPieces[9][0] = Piece.Chariot;
        originalPieces[9][8] = Piece.Chariot;
        originalPieces[0][1] = Piece.Horse;
        originalPieces[0][7] = Piece.Horse;
        originalPieces[9][1] = Piece.Horse;
        originalPieces[9][7] = Piece.Horse;
        originalPieces[0][2] = Piece.Elephant;
        originalPieces[0][6] = Piece.Elephant;
        originalPieces[9][2] = Piece.Elephant;
        originalPieces[9][6] = Piece.Elephant;
        originalPieces[0][3] = Piece.Advisor;
        originalPieces[0][5] = Piece.Advisor;
        originalPieces[9][3] = Piece.Advisor;
        originalPieces[9][5] = Piece.Advisor;
        originalPieces[2][1] = Piece.Cannon;
        originalPieces[2][7] = Piece.Cannon;
        originalPieces[7][1] = Piece.Cannon;
        originalPieces[7][7] = Piece.Cannon;
        originalPieces[3][0] = Piece.Soldier;
        originalPieces[3][2] = Piece.Soldier;
        originalPieces[3][4] = Piece.Soldier;
        originalPieces[3][6] = Piece.Soldier;
        originalPieces[3][8] = Piece.Soldier;
        originalPieces[6][0] = Piece.Soldier;
        originalPieces[6][2] = Piece.Soldier;
        originalPieces[6][4] = Piece.Soldier;
        originalPieces[6][6] = Piece.Soldier;
        originalPieces[6][8] = Piece.Soldier;
    }

    /**
     * Create 20 rooms
     */
    function _initializeRooms() private {
        for (uint8 i = 1; i <= 20; i++) {
            rooms.push(Room(i,  [address(0), address(0)], 0, 0, MAX_GAME_DURATION, false));
        }
    }

    /* External Views */

    function getAllRooms() external view returns (Room[] memory) {
        return rooms;
    }

//    function getAllMatches() external view returns (Match[] memory) {
//        return matches;
//    }

    function getMatch(uint256 id) external view returns (Match memory) {
        return matches[matchIndexes[id]];
    }

    function getAllPlayers() external view returns (Player[] memory) {
        return players;
    }

    function getPlayer(address _addr) external view returns (Player memory) {
        return players[playerIndexes[_addr]];
    }

    function isPlayer(address _addr) external view returns (bool) {
        return playerIndexes[_addr] != 0;
    }

    /**/

    // Team color is not a concern in this function, so elements of Match.players are accessed using number directly.
    function joinRoom(uint256 roomNumber) external {
        Room memory _room = rooms[roomNumber];

        require(_room.number != 0, "Room does not exist");
        require(_room.players[0] == address(0) || _room.players[1] == address(0), "The room is full");

        // Reset empty room's data if there's no player is in
        if (_room.players[0] == address(0) && _room.players[1] == address(0)) {
            _resetRoomInfo(roomNumber);
        }

        if (_room.players[0] == address(0)) {
            rooms[roomNumber].players[0] = _msgSender();
        } else {
            rooms[roomNumber].players[1] = _msgSender();
        }

        players[playerIndexes[_msgSender()]].roomNumber = roomNumber;
    }

    // TODO: handle the case when game has started
    function exitRoom(uint256 roomNumber) external joiningRoom(roomNumber) {
        Match _match = matches[matchIndexes[roomNumber]];
        uint8 currentPlayerIndex = _match.players[0] == _msgSender() ? 0 : 1;
        uint8 remainingPlayerIndex = currentPlayerIndex == 0 ? 1 : 0;

        if (_match.players[remainingPlayerIndex] != address(0)) {
            if (remainingPlayerIndex == 1) { // & current = 0
                remainingPlayerIndex = 0;
                _match.players[0] = _match.players[1];
            }

            _match.players[1] = address(0);

            // Transfer host role to the remaining player and leave; should only happen if current's index = 1 && remaining's index = 0
            if (currentPlayerIndex != remainingPlayerIndex && _match.hostIndex == currentPlayerIndex) {
                _match.hostIndex = remainingPlayerIndex;
            }

            players[playerIndexes[_msgSender()]].inRoom = false;
        } else {
            // Reset room's data if no player resides
            _resetRoomInfo(roomNumber);
        }
    }

    // Free players in the room (if exists any) before removing
    function _resetRoomInfo(uint256 roomNumber) private {
        Room memory _room = rooms[roomNumber];

        if (_room.players[0] != address(0)) {
            players[rooms[roomNumber].players[0]].roomNumber = 0;
        }

        if (_room.players[1] != address(0)) {
            players[rooms[roomNumber].players[1]].roomNumber = 0;
        }

        // Replace position of last match with position of current match in the 'matches' array

        _room = matches[matches.length - 1];
        matchIndexes[matches[matches.length - 1].id] = matchIndex;
        // then remove the last element (a.k.a. currentMatch)
        matches.pop();
        delete matchIndexes[matchIndex];
    }

    function startNewMatch(string calldata name) external returns (Match memory newMatch) {
        uint256 matchId = uint256(keccak256(abi.encodePacked(_msgSender(), block.timestamp, name)));
        PlayerPiece[10][9] memory emptyBoard;
        newMatch = Match(matchId, name, GameStatus.PENDING, emptyBoard, [_msgSender(), address(0)]);

        matchIndexes[matchId] = matches.length;
        matches.push(newMatch);

        return newMatch;
    }

    function startGame(uint256 matchId) external payable joiningRoom(matchId) {
        Match memory _match = matches[matchIndexes[matchId]];

        require(_match.id != 0, "The match does not exist");
        require(_match.players[0] != address(0) && _match.players[1] != address(0), "Not enough player to start");
        require(_msgSender() == _match.players[0] || _msgSender() == _match.players[1]); // allow any of 2 players to start the game

        _match.board = _initBoard();
        // TODO: set timestamp for the time starting game,...
    }

    function _initBoard() private returns (PlayerPiece[9][] memory) {
        PlayerPiece[9] memory firstRow;
        PlayerPiece[9] memory secondRow;
        PlayerPiece[9] memory thirdRow;
        PlayerPiece[9] memory fourthRow;
        PlayerPiece[9] memory fifthRow;
        PlayerPiece[9] memory sixthRow;
        PlayerPiece[9] memory seventhRow;
        PlayerPiece[9] memory eighthRow;
        PlayerPiece[9] memory ninthRow;
        PlayerPiece[9] memory tenthRow;

        PlayerPiece[9][] memory board = new PlayerPiece[9][](10);

        board[0] = firstRow;
        board[1] = secondRow;
        board[2] = thirdRow;
        board[3] = fourthRow;
        board[4] = fifthRow;
        board[5] = sixthRow;
        board[6] = seventhRow;
        board[7] = eighthRow;
        board[8] = ninthRow;
        board[9] = tenthRow;

        firstRow[letterToIndex['E']] = PlayerPiece(RED, Piece.General, false);
        tenthRow[letterToIndex['E']] = PlayerPiece(BLACK, Piece.General, false);

        // Init using random (keccak256... % 15)
        PlayerPiece[15] memory redTeam = _generateRandomlyOrderedNonGeneralPieceList(RED);
        PlayerPiece[15] memory blackTeam = _generateRandomlyOrderedNonGeneralPieceList(BLACK);

        // Assign to right positions
        uint8 pieceIndex = 0; // index of the 2 nearest arrays above

        // First row of each team
        for (uint8 col = 0; col < 9; col++) {
            if (col == 4) continue; // ignore position of General

            board[0][col] = redTeam[pieceIndex];
            board[9][col] = blackTeam[pieceIndex];
            pieceIndex++;
        }

        // Third row of each team (containing only Cannons originally)
        board[2][1] = redTeam[pieceIndex];
        board[2][7] = redTeam[pieceIndex];
        pieceIndex++;
        board[7][1] = redTeam[pieceIndex];
        board[7][7] = redTeam[pieceIndex];
        pieceIndex++;

        // Fourth row of each team (containing only Soldiers originally)
        for (uint8 col = 0; col < 9; col += 2) {
            board[3][col] = redTeam[pieceIndex];
            board[6][col] = redTeam[pieceIndex];
            pieceIndex++;
        }

        return board;
    }

    function _generateRandomlyOrderedNonGeneralPieceList(uint8 color) private returns (PlayerPiece[15] memory) {
        require(color == RED || color == BLACK, "color must be either RED or BLACK");

        Piece[15] memory allNonGeneralPieces = [Piece.Advisor, Piece.Soldier, Piece.Cannon, Piece.Soldier, Piece.Chariot,
                        Piece.Elephant, Piece.Soldier, Piece.Advisor, Piece.Horse, Piece.Soldier,
                        Piece.Elephant, Piece.Cannon, Piece.Soldier, Piece.Chariot, Piece.Horse];
        PlayerPiece[15] memory returnedPieceList;
        uint8 numOfLeftPieces = uint8(allNonGeneralPieces.length);
        int8 lastSortedPiece = - 1;

        // Gradually put each element (piece) in the allNonGeneralPieces list into returnedPieceList
        for (uint i = 0; i < 15; i++) {
            uint8 random = uint8(uint256(keccak256(abi.encodePacked(_msgSender(), block.timestamp, lastSortedPiece))) % numOfLeftPieces);

            returnedPieceList[i] = PlayerPiece(color, allNonGeneralPieces[uint256(random)], false);
            lastSortedPiece = int8(random);
            numOfLeftPieces--;
            // Copy last element to the position of the selected element, then delete that selected element (which now also is the last element in array)
            allNonGeneralPieces[random] = allNonGeneralPieces[numOfLeftPieces];

            delete allNonGeneralPieces[numOfLeftPieces];
        }

        return returnedPieceList;
    }

    function move(uint8 sourceRow, uint8 sourceCol, uint8 destRow, uint8 destCol) external payable returns (bool) {
        // TODO: implement this in next version
        return true;
    }

    function requestToDraw(uint256 matchId) external payable {
        // TODO: implement this in next version
        revert();
    }

    function surrender(uint256 matchId) external payable {
        // TODO: implement this in next version
        revert();
    }
}
