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
    event NewPlayer(address _address, string name);
    event NewTableCreated(uint256 id, string name, address hostAddress);
    event NewGameStarted(string gameName, address player1, address player2);
    event MatchEnded(uint256 matchId, MatchResult matchResult, address winner, address loser);

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

    enum GameMode {
        None,
        Bot,
        Normal, // PvP
        Rank
    }

    enum MatchStatus {
        Started,
        Paused,
        Ended
    }

    enum MatchResultType {
        None,
        // Win reasons //
        Checkmate,
        Timeout,
        OutOfTurns,
        FiveFold,
        Resign,
        LeaveMatch,
        ////
        // Draw reasons //
        Stalemate,
        /* Require index of the player had offered */
        OfferToDraw
        ////
    }

    struct Player {
        address playerAddress;
        string playerName;
        uint32 elo;
        uint256 tableId; // Store a reference to the table that player is currently in (0 if not in any table)
    }

    struct Table {
        uint256 id;
        GameMode gameMode;
        string name;
        address[2] players; // should be accessed using the constants 'BLACK', 'RED'
        /**
         * Index of the 'players' array; equals either 0 or 1.
         */
        uint8 hostIndex;
        uint256 stake;
        uint24 timeControl;
        uint256 matchId; // 0 if game hasn't started, and > 0 otherwise
        // TODO: may allow audiences to join
    }

    struct MatchResult {
        uint8 winnerIndex;
        MatchResultType resultType;
        uint8 increasingElo;
        uint8 decreasingElo;
    }

    struct Position {
        uint8 row;
        uint8 column;
    }

    struct PlayerPiece {
        uint8 color; // either RED (0) or BLACK (1)
        Piece piece;
        bool unfolded; // 2 purposes: (1) identify if a piece has moved or not and (2) decide the rule of its next move will comply with the rule of which Piece
    }

    struct Match {
        uint256 id;
        GameMode gameMode;
        //        uint256 tableId;
        address[2] players; // should be accessed using the constants 'BLACK', 'RED'
        uint256 stake;
        uint24 timeControl;
        uint256 startTimestamp;
        uint256 endTimestamp;
        MatchStatus gameStatus;
        MatchResult matchResult;
        PlayerPiece[9][10] board;
        Position[2][] steps;
    }

    /* State variables */

    Player[] public players;
    mapping(address => uint256) public playerIndexes; // player's address => player's index
    Table[] public tables;
    mapping(GameMode => uint256[]) public typeTableMapping;
    Match[] public matches;
    //    mapping(uint256 => uint256) public matchIndexes; // game's id => game's index (of 'matches' array)

    /**
     * May use this to understand piece moves sent from client.
     * Initialized & filled with data only once when constructing this contract.
     */
    mapping(string => uint8) internal letterToIndex;

    /**
     * Use this to identify a piece based on its original position.
     * Initialized & filled with data only once when constructing this contract.
     *
     * Read-only.
     */
    Piece[9][10] public originalPieces;
    PlayerPiece nullPiece = PlayerPiece(2, Piece.None, true);

    //    string public baseURI;
    //    uint public totalSupply;

    /**/

    /* Modifiers */

    modifier playerExists() {
        require(this.isPlayer(_msgSender()), "You are not player");
        _;
    }

    modifier playerAddrExists(address addr) {
        require(this.isPlayer(addr), "This is not player");
        _;
    }

    modifier tableExists(uint256 tableId) {
        require(tables[tableId].id != 0, "Table does not exist");
        _;
    }

    modifier matchExists(uint256 matchId) {
        require(matches[matchId].id != 0, "The match does not exist");
        _;
    }

    modifier joiningTable(uint256 tableId) {
        require(this.isPlayer(_msgSender()), "You are not player");
        _;
        require(tables[tableId].id != 0, "Table does not exist");

        Table memory _table = tables[tableId];
        address[2] memory _playerAddresses = _table.players;

        require(
            _msgSender() == _playerAddresses[0] ||
                _msgSender() == _playerAddresses[1],
            "You are not in this table"
        );
        _;
    }

    //    modifier matchExists(uint256 matchId) {
    //        require(matches[matchIndexes[matchId]].id != 0, "The match does not exist");
    //        _;
    //    }

    /**/

    /* Constructor & getters */

    constructor() payable Ownable(_msgSender()) {
        _initialize();
        _initializeOriginalPieces();
    }

    function _initialize() private {
        PlayerPiece[9][10] memory emptyBoard;
        Position[2][] memory emptySteps;

        players.push(Player(address(0), "", 0, 0));
        tables.push(
            Table(0, GameMode.None, "", [address(0), address(0)], 0, 0, 0, 0)
        );
        matches.push(
            Match(
                0,
                GameMode.None,
                [address(0), address(0)],
                0,
                0,
                0,
                0,
                MatchStatus.Ended,
                MatchResult(0, MatchResultType.None, 0, 0),
                emptyBoard,
                emptySteps
            )
        );

        letterToIndex["A"] = 0;
        letterToIndex["B"] = 1;
        letterToIndex["C"] = 2;
        letterToIndex["D"] = 3;
        letterToIndex["E"] = 4;
        letterToIndex["F"] = 5;
        letterToIndex["G"] = 6;
        letterToIndex["H"] = 7;
        letterToIndex["I"] = 8;
        letterToIndex["J"] = 9;
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

    //    /**
    //     * Create 20 tables
    //     */
    //    function _initializeTables() private {
    //        for (uint8 i = 1; i <= 20; i++) {
    //            tables.push(Table(i, [address(0), address(0)], 0, 0, MAX_GAME_DURATION, false));
    //        }
    //    }

    /* External Views */

    function getAllPlayers() external view returns (Player[] memory) {
        return players;
    }

    function getAllPlayersByDescendingRank()
        external
        view
        returns (Player[50] memory _players)
    {}

    function getPlayer(
        address _addr
    ) external view playerAddrExists(_addr) returns (Player memory) {
        return players[playerIndexes[_addr]];
    }

    function isPlayer(address _addr) external view returns (bool) {
        return playerIndexes[_addr] != 0;
    }

    function getAllMatches() external view returns (Match[] memory) {
        return matches;
    }

    function getMatch(
        uint256 id
    ) external view matchExists(id) returns (Match memory) {
        return matches[id];
    }

    function getAllTables(
        GameMode gameMode
    ) external view returns (Table[] memory _tables) {
        if (gameMode == GameMode.None) {
            return tables;
        }

        // TODO: emplement pagination
    }

    function getTable(
        uint256 id
    ) external view tableExists(id) returns (Table memory) {
        return tables[id];
    }

    /**/

    /* Main logics */

  function registerPlayer(string memory _name) external {
    require(!this.isPlayer(_msgSender()), "Player already registered"); // Require that player is not already registered
    
    uint256 _id = players.length;
    players.push(Player(_msgSender(), _name, 0, 0)); // Add player to players array
    playerIndexes[_msgSender()] = _id; // Create player's address - index mapping

    
    emit NewPlayer(_msgSender(), _name); // Emits NewPlayer event
  }

    function createTable(
        GameMode gameMode,
        string calldata name,
        uint256 stake
    ) external {
        tables.push(
            Table({
                id: tables.length,
                gameMode: gameMode,
                name: name,
                players: [_msgSender(), address(0)],
                hostIndex: 0,
                stake: stake,
                timeControl: 20 * 60,
                matchId: 0
            })
        );
        Table memory _table = tables[tables.length];
        this.getPlayer(_msgSender()).tableId = _table.id;

        // typeTableMapping[gameMode].push(_table);
    }

    // Team color is not a concern in this function, so elements of Match.players are accessed using number directly.
    function joinTable(uint256 tableId) external tableExists(tableId) {
        Table memory _table = tables[tableId];

        require(_table.id != 0, "Table does not exist");
        require(
            _table.players[0] == address(0) || _table.players[1] == address(0),
            "The table is full"
        );

        // Remove table if there's no player is in
        if (
            _table.players[0] == address(0) && _table.players[1] == address(0)
        ) {
            _removeTable(tableId);

            revert("The table is not found");
        }

        if (_table.players[0] == address(0)) {
            tables[tableId].players[0] = _msgSender();
        } else {
            tables[tableId].players[1] = _msgSender();
        }

        this.getPlayer(_msgSender()).tableId = tableId;
    }

    // TODO: handle the case when game has started
    function exitTable(uint256 tableId) external joiningTable(tableId) {
        Table memory _table = tables[tableId];
        uint8 currentPlayerIndex = (_table.players[0] == _msgSender()) ? 0 : 1;
        uint8 remainingPlayerIndex = 1 - currentPlayerIndex;

        this.getPlayer(_msgSender()).tableId = 0;

        // If there's 1 player left, assign that player to index 0 and transfer table ownership
        if (_table.players[remainingPlayerIndex] != address(0)) {
            if (remainingPlayerIndex == 1) {
                // -> currentPlayerIndex = 0
                _table.players[currentPlayerIndex] = _table.players[
                    remainingPlayerIndex
                ];
                remainingPlayerIndex = 0;
            }

            _table.players[1 - remainingPlayerIndex] = address(0);
            // Transfer host role to the remaining player and leave
            _table.hostIndex = remainingPlayerIndex;
        } else {
            // Remove table if no player reside
            _removeTable(tableId);
        }
    }

    // Free players in the table (if exists any) before removing
    function _removeTable(uint256 tableId) private tableExists(tableId) {
        Table memory _table = tables[tableId];

        for (uint8 i = 0; i <= 1; i++) {
            if (_table.players[i] != address(0)) {
                this.getPlayer(tables[tableId].players[i]).tableId = 0;
            }
        }

        // Put the last element in "tables" array to position of the target table
        _table = tables[tables.length - 1];
        tables[tableId] = _table;
        this.getPlayer(_table.players[0]).tableId = tableId;
        this.getPlayer(_table.players[1]).tableId = tableId;
        // then remove the last element/table
        tables.pop();
    }

    function startNewMatch(
        uint256 tableId
    ) external payable joiningTable(tableId) returns (Match memory newMatch) {
        Table memory _table = tables[this.getPlayer(_msgSender()).tableId];

        require(
            _table.players[0] != address(0) && _table.players[1] != address(0),
            "Not enough players to start"
        );

        uint256 matchId = uint256(
            keccak256(
                abi.encodePacked(_msgSender(), block.timestamp, _table.id)
            )
        );
        // PlayerPiece[9][10] memory emptyBoard;
        Position[2][] memory emptyStepList;

        _table.matchId = matchId;
        newMatch = Match({
            id: matchId,
            gameMode: _table.gameMode,
            players: _table.players,
            stake: _table.stake,
            timeControl: _table.timeControl,
            startTimestamp: block.timestamp,
            endTimestamp: 0,
            gameStatus: MatchStatus.Started,
            board: _initBoard(),
            matchResult: MatchResult(0, MatchResultType.None, 10, 10),
            steps: emptyStepList
        });

        matches.push(newMatch);
    }

    function _initBoard() private returns (PlayerPiece[9][10] memory) {
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

        PlayerPiece[9][10] memory board;

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

        firstRow[4] = PlayerPiece(RED, Piece.General, true);
        tenthRow[4] = PlayerPiece(BLACK, Piece.General, true);

        // Init using random (keccak256... % 15)
        PlayerPiece[15]
            memory redTeam = _generateRandomlyOrderedNonGeneralPieceList(RED);
        PlayerPiece[15]
            memory blackTeam = _generateRandomlyOrderedNonGeneralPieceList(
                BLACK
            );

        // Assign to right positions
        uint8 pieceIndex = 0; // index of both redTeam & blackTeam

        // First row of each team
        for (uint8 col = 0; col < 9; col++ >= 0 && pieceIndex++ >= 0) {
            if (col == 4) continue; // ignore position of General

            firstRow[col] = redTeam[pieceIndex];
            tenthRow[col] = blackTeam[pieceIndex];
        }

        // Third row of each team (containing only Cannons originally)
        thirdRow[1] = redTeam[pieceIndex];
        thirdRow[8 - 1] = redTeam[pieceIndex];
        pieceIndex++;
        eighthRow[1] = blackTeam[pieceIndex];
        eighthRow[8 - 1] = blackTeam[pieceIndex];
        pieceIndex++;

        // Fourth row of each team (containing only Soldiers originally)
        for (uint8 col = 0; col < 9;) {
            fourthRow[col] = redTeam[pieceIndex];
            seventhRow[col] = blackTeam[pieceIndex];
            
            pieceIndex++;
            col += 2;
        }

        return board;
    }

    function _generateRandomlyOrderedNonGeneralPieceList(
        uint8 color
    ) private returns (PlayerPiece[15] memory) {
        require(
            color == RED || color == BLACK,
            "color must be either RED or BLACK"
        );

        Piece[15] memory allNonGeneralPieces = [
            Piece.Advisor,
            Piece.Soldier,
            Piece.Cannon,
            Piece.Soldier,
            Piece.Chariot,
            Piece.Elephant,
            Piece.Soldier,
            Piece.Advisor,
            Piece.Horse,
            Piece.Soldier,
            Piece.Elephant,
            Piece.Cannon,
            Piece.Soldier,
            Piece.Chariot,
            Piece.Horse
        ];
        PlayerPiece[15] memory returnedPieceList;
        uint8 numOfLeftPieces = uint8(allNonGeneralPieces.length);
        int8 lastSortedPiece = -1;

        // Gradually put each element (piece) in the allNonGeneralPieces list into returnedPieceList
        for (uint i = 0; i < 15; i++) {
            uint8 random = uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            _msgSender(),
                            block.timestamp,
                            lastSortedPiece
                        )
                    )
                ) % numOfLeftPieces
            );

            returnedPieceList[i] = PlayerPiece(
                color,
                allNonGeneralPieces[uint256(random)],
                false
            );
            lastSortedPiece = int8(random);
            numOfLeftPieces--;
            // Copy last element to the position of the selected element, then delete that selected element (which now also is the last element in array)
            allNonGeneralPieces[random] = allNonGeneralPieces[numOfLeftPieces];

            delete allNonGeneralPieces[numOfLeftPieces];
        }

        return returnedPieceList;
    }

    function move(
        uint8 sourceRow,
        uint8 sourceCol,
        uint8 destRow,
        uint8 destCol
    ) external payable returns (bool) {
        require(
            (sourceRow >= 0 && sourceRow < 10) &&
                (destRow >= 0 && destRow < 10) &&
                (sourceCol >= 0 && sourceCol < 9) &&
                (destCol >= 0 && destCol < 9)
        );

        Player memory _player = this.getPlayer(_msgSender());

        require(_player.tableId != 0, "You hasn't been being in any table");

        Table memory _table = tables[_player.tableId];

        require(_table.matchId != 0, "Game hasn't been started");

        Match memory _match = matches[_table.matchId];
        uint8 playerColor = (_match.players[RED] == _msgSender())
            ? RED
            : (_match.players[BLACK] == _msgSender())
            ? BLACK
            : 2;

        require(playerColor == 2, "You hasn't been being in any match");

        PlayerPiece[9][10] memory board = _match.board;

        require(
            board[sourceRow][sourceCol].color == playerColor,
            "Invalid move"
        );

        // TODO: may verify move by rules of specific piece
        board[destRow][destCol] = board[sourceRow][destCol];
        board[sourceRow][sourceRow] = nullPiece;
        board[destRow][destCol].unfolded = true;

        return true;
    }

    function verifyCheckmate(uint256 matchId ) external payable {
        // TODO: implement this in next version
    }

    function offerDraw(uint256 matchId) external payable {
        // TODO: implement this in next version
    }

    function resign(uint256 matchId) external payable {
        // TODO: implement this in next version
        revert();
    }
}
