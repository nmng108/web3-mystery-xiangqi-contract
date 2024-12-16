// SPDX-License-Identifier: UNLICENSED
pragma solidity ~0.8.20;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MysteryChineseChess is Ownable {
    /**
     * Set a 30-minute time control at maximum and by default for each player.
     * Unit: millisecond
     */
    uint24 public constant MAX_TIME_CONTROL = 30 * 60 * 1000 /*milliseconds*/;
    // Represent color of piece; use this constant to retrieve players in a game
    uint8 public constant RED = 0;
    uint8 public constant BLACK = 1;

    //? "indexed" keyword should be with address param?
    event NewPlayer(Player player);
    event UpdatedPlayerInfo(address playerAddress);
    event NewTableCreated(Table table);
    event JoinedTable(address playerAddress, uint256 tableId);
    event UpdatedTable(Table table);
    event UpdatedTableId(uint256 oldTableId, uint256 newTableId);
    event ExitedTable(address playerAddress, uint256 tableId);
    event NewMatchStarted(uint256 matchId, address[2] players);
    event MatchEnded(Match _match);
    event OfferingDraw(uint256 matchId, address playerAddress);
    event ApprovedDrawOffer(uint256 matchId, address playerAddress);
    event DeclinedDrawOffer(uint256 matchId, address playerAddress);

    error Unauthorized();
    error ResourceNotFound(string message);
    error InvalidAction(string message);

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
        Beginner,
        Intermediate,
        Advanced,
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
        Draw, // requires auto-detection and also both players to approve
        /* Require index of the player had offered */
        OfferToDraw // requires both players to approve
        ////
    }

    enum Vote {
        None,
        Approve,
        Decline
    }

    struct Player {
        address playerAddress;
        string playerName;
        int32 elo;
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
        uint32 stake;
        uint24 timeControl;
        uint256 matchId; // 0 if game hasn't started, and > 0 otherwise
        // TODO: may allow audiences to join
    }

    struct MatchResult {
        uint8 winnerIndex;
        uint8 offererIndex;
        MatchResultType resultType;
        uint32 increasingElo;
        uint32 decreasingElo;
    }

    struct Position {
        uint8 y;
        uint8 x;
    }

    struct MoveDetails {
        uint8 playerIndex;
        Position oldPosition;
        Position newPosition;
        uint256 timestamp;
    }

    struct Move {
        MoveDetails details;
        string[2] signatures;
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
        uint32 stake;
        uint24 timeControl;
        uint256 startTimestamp;
        uint256 endTimestamp;
        MatchStatus matchStatus;
        MatchResult matchResult;
        PlayerPiece[9][10] board;
        Move[] moves;
    }

    /* State variables */

    IERC20 tokenContract;
    Player[] public players;
    mapping(address => uint256) public playerIndexes; // player's address => player's index
    Table[] public tables;
    uint256[] public normalModeBeginnerTableIndexes;
    uint256[] public normalModeIntermediateTableIndexes;
    uint256[] public normalModeAdvancedTableIndexes;
    uint256[] public rankModeTableIndexes;
    Match[] public matches;
    mapping(uint256 => uint256) public matchIndexes; // match's ID => match's index (of 'matches' array)
    /**
     * Store votes of matches that have players offering draw.
     * Match's ID => array of votes
     */
    mapping(uint256 => Vote[]) public drawVotes;

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
        if (!this.isPlayer(_msgSender())) {
            revert Unauthorized();
        }

        _;
    }

    // modifier playerAddrExists(address addr) {
    //     require(this.isPlayer(addr), "This is not player");
    //     _;
    // }

    modifier tableExists(uint256 tableId) {
        if (tables[tableId].id == 0) {
            revert ResourceNotFound("Table does not exist");
        }

        _;
    }

    modifier matchExists(uint256 matchId) {
        if (matchIndexes[matchId] == 0) {
            revert ResourceNotFound("The match does not exist");
        }

        _;
    }

    modifier joiningTable(uint256 tableId) {
        if (!this.isPlayer(_msgSender())) {
            revert Unauthorized();
        }

        if (tables[tableId].id == 0) {
            revert ResourceNotFound("Table does not exist");
        }

        Table memory _table = tables[tableId];
        address[2] memory _playerAddresses = _table.players;

        if (
            _msgSender() != _playerAddresses[0] &&
            _msgSender() != _playerAddresses[1]
        ) {
            revert InvalidAction("You are not in this table");
        }

        _;
    }

    modifier joiningMatch(uint256 matchId) {
        if (matchIndexes[matchId] == 0) {
            revert ResourceNotFound("The match does not exist");
        }

        Match memory _match = matches[matchIndexes[matchId]];
        address[2] memory _playerAddresses = _match.players;

        if (
            _msgSender() != _playerAddresses[0] &&
            _msgSender() != _playerAddresses[1]
        ) {
            revert InvalidAction("You are not joining this match");
        }

        _;
    }

    /**/

    /* Constructor & getters */

    constructor(/*address tokenAddress*/) payable Ownable(_msgSender()) {
        _initialize();
        _initializeOriginalPieces();
        // tokenContract = IERC20(tokenAddress);
    }

    function _initialize() private {
        PlayerPiece[9][10] memory emptyBoard;
        Move[] memory emptySteps;

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
                MatchResult(0, 2, MatchResultType.None, 0, 0),
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
        originalPieces[0][4] = Piece.General;
        originalPieces[9][4] = Piece.General;
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
     * Create 20 tables
     */
    // function initializeTables() external payable onlyOwner {
    //     for (uint8 i = 1; i <= 20; i++) {
    //         tables.push(
    //             Table(
    //                 uint256(i),
    //                 GameMode.Rank,
    //                 string.concat("Room ", Strings.toString(uint256(i))),
    //                 [address(0), address(0)],
    //                 0,
    //                 0,
    //                 0,
    //                 0
    //             )
    //         );
    //     }
    // }

    /* External Views */

    function getAllPlayers() external view returns (Player[] memory) {
        return players;
    }

    // function getAllPlayersByDescendingRank()
    //     external
    //     view
    //     returns (Player[] memory _players)
    // {

    // }

    function getPlayer(address _addr) external view returns (Player memory) {
        if (!this.isPlayer(_addr)) {
            revert ResourceNotFound("Player does not exist");
        }

        return players[playerIndexes[_addr]];
    }

    function _getPlayer(address _addr) internal view returns (Player storage) {
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
        return matches[matchIndexes[id]];
    }

    function getAllTables(
        GameMode gameMode,
        uint24 page,
        uint16 size
    ) external view returns (Table[] memory) {
        Table[] memory _returnedTables = new Table[](size);

        if (gameMode == GameMode.None) {
            for (
                uint256 i = (page - 1) * size;
                i < (page - 1) * size + size;
                i++
            ) {
                if (i == tables.length) {
                    break;
                }

                _returnedTables[i] = tables[i];
            }

            return _returnedTables;
        }

        uint256[] storage tableIndexes = _getTableIndexesByGameMode(gameMode);

        for (
            uint256 i = (page - 1) * size;
            i < (page - 1) * size + size - 1;
            i++
        ) {
            console.log(i);

            if (i >= tableIndexes.length) {
                break;
            }

            _returnedTables[i] = tables[tableIndexes[i]];
        }

        return _returnedTables;
    }

    function _getTableIndexesByGameMode(
        GameMode gameMode
    ) private view returns (uint256[] storage tableIndexes) {
        if (gameMode == GameMode.Beginner) {
            tableIndexes = normalModeBeginnerTableIndexes;
        } else if (gameMode == GameMode.Intermediate) {
            tableIndexes = normalModeIntermediateTableIndexes;
        } else if (gameMode == GameMode.Advanced) {
            tableIndexes = normalModeAdvancedTableIndexes;
        } else if (gameMode == GameMode.Rank) {
            tableIndexes = rankModeTableIndexes;
        } else {
            revert InvalidAction("Invalid GameMode");
        }
    }

    function getTable(
        uint256 id
    ) external view tableExists(id) returns (Table memory) {
        return tables[id];
    }

    /**/

    /* Main logics */

    function registerPlayer(string calldata _name) external {
        require(!this.isPlayer(_msgSender()), "Player already registered"); // Require that player is not already registered

        if (bytes(_name).length == 0) {
            revert InvalidAction("Name cannot be empty");
        }

        uint256 _id = players.length;
        Player memory _player = Player(_msgSender(), _name, 100, 0);
        players.push(_player); // Add player to players array
        playerIndexes[_msgSender()] = _id; // Create player's address - index mapping

        // tokenContract.transferFrom(owner(), _msgSender(), 200);

        emit NewPlayer(_player);
    }

    function updatePlayer(
        string calldata playerName,
        uint256 tableId,
        bool setsTableId
    ) external playerExists {
        Player storage s_player = players[playerIndexes[_msgSender()]];

        if (
            (bytes(playerName).length > 0) &&
            keccak256(abi.encodePacked(playerName)) !=
            keccak256(abi.encodePacked(s_player.playerName))
        ) {
            s_player.playerName = playerName;
        }

        if (setsTableId) {
            s_player.tableId = tableId;
        }

        emit UpdatedPlayerInfo(_msgSender());
    }

    function createTable(
        GameMode gameMode,
        string calldata name,
        uint32 stake
    ) external {
        uint256 tableId = tables.length;
        Table memory _table = Table({
            id: tableId,
            gameMode: gameMode,
            name: name,
            players: [_msgSender(), address(0)],
            hostIndex: 0,
            stake: stake,
            timeControl: MAX_TIME_CONTROL,
            matchId: 0
        });

        tables.push(_table);
        _getPlayer(_msgSender()).tableId = tableId;

        if (gameMode == GameMode.Beginner) {
            normalModeBeginnerTableIndexes.push(tableId);
        } else if (gameMode == GameMode.Intermediate) {
            normalModeIntermediateTableIndexes.push(tableId);
        } else if (gameMode == GameMode.Advanced) {
            normalModeAdvancedTableIndexes.push(tableId);
        } else if (gameMode == GameMode.Rank) {
            rankModeTableIndexes.push(tableId);
        } else {
            revert InvalidAction("Invalid GameMode. Cannot create table");
        }

        emit NewTableCreated(_table);
    }

    function updateTable(
        uint256 tableId,
        string memory name,
        uint24 timeControl,
        uint32 stake
    ) external tableExists(tableId) {
        Table storage s_table = tables[tableId];

        if (
            (bytes(name).length > 0) &&
            keccak256(abi.encodePacked(name)) !=
            keccak256(abi.encodePacked(s_table.name))
        ) {
            s_table.name = name;
        }

        if ((stake > 0) && (stake != s_table.stake)) {
            s_table.stake = stake;
        }

        if ((timeControl > 0) && (timeControl != s_table.timeControl)) {
            s_table.timeControl = timeControl;
        }

        emit UpdatedTable(s_table);
    }

    // Team color is not a concern in this function, so elements of Match.players are accessed using number directly.
    function joinTable(uint256 tableId) external tableExists(tableId) {
        Table storage table = tables[tableId];
        uint8 emptySlot = 2;

        if (table.players[1] == address(0)) {
            emptySlot = 1;
        }

        if (table.players[0] == address(0)) {
            emptySlot = 0;
        }

        if (emptySlot == 2) {
            revert InvalidAction("The table is full");
        }

        table.players[emptySlot] = _msgSender();
        _getPlayer(_msgSender()).tableId = tableId;

        if (table.players[0] == address(0) && table.players[1] == address(0)) {
            table.hostIndex = 0;
        }

        emit JoinedTable(_msgSender(), tableId);
    }

    /**
     * Allow requesting player to exit current table.
     */
    function exitTable(uint256 tableId) external joiningTable(tableId) {
        _getPlayer(_msgSender()).tableId = 0;

        Table storage table = tables[tableId];
        uint8 currentPlayerIndex = (table.players[0] == _msgSender()) ? 0 : 1;
        uint8 remainingPlayerIndex = 1 - currentPlayerIndex;

        // If there's 1 player left, assign that player to index 0 and transfer table ownership
        if (table.players[remainingPlayerIndex] != address(0)) {
            if (remainingPlayerIndex == 1) {
                // -> currentPlayerIndex = 0
                table.players[currentPlayerIndex] = table.players[
                    remainingPlayerIndex
                ];
                remainingPlayerIndex = 0;
            }

            table.players[1 - remainingPlayerIndex] = address(0);
            // Transfer host role to the remaining player and leave
            table.hostIndex = remainingPlayerIndex;
        } else {
            // Remove table if no player reside
            console.log(
                string.concat(
                    "player.tableId = ",
                    Strings.toString(_getPlayer(_msgSender()).tableId)
                ),
                ". Start to delete table"
            );
            _removeTable(tableId);
        }

        emit ExitedTable(_msgSender(), tableId);
    }

    /**
     * Allow requesting player to exit current table.
     */
    function _exitTable(uint256 tableId) private joiningTable(tableId) {
        console.log("(inside) Start exitTable function");
        _getPlayer(_msgSender()).tableId = 0;

        Table storage table = tables[tableId];
        uint8 currentPlayerIndex = (table.players[0] == _msgSender()) ? 0 : 1;
        uint8 remainingPlayerIndex = 1 - currentPlayerIndex;
        console.log("(inside) retrieved table data in exitTable function");

        // If there's 1 player left, assign that player to index 0 and transfer table ownership
        if (table.players[remainingPlayerIndex] != address(0)) {
            if (remainingPlayerIndex == 1) {
                // -> currentPlayerIndex = 0
                table.players[currentPlayerIndex] = table.players[
                    remainingPlayerIndex
                ];
                remainingPlayerIndex = 0;
            }

            table.players[1 - remainingPlayerIndex] = address(0);
            // Transfer host role to the remaining player and leave
            table.hostIndex = remainingPlayerIndex;
        } else {
            // Remove table if no player reside
            console.log(
                string.concat(
                    "player.tableId = ",
                    Strings.toString(_getPlayer(_msgSender()).tableId)
                ),
                ". Start to delete table"
            );
            _removeTable(tableId);
        }
        console.log("(inside) Ended exitTable function");

        emit ExitedTable(_msgSender(), tableId);
    }

    // Free players in the table (if exists any) before removing
    function _removeTable(uint256 tableId) private tableExists(tableId) {
        Table memory _table = tables[tableId];

        for (uint8 i = 0; i <= 1; i++) {
            if (_table.players[i] != address(0)) {
                _getPlayer(_table.players[i]).tableId = 0;
                console.log(
                    string.concat(
                        "(in loop) Player ",
                        Strings.toString(i),
                        " has tableId changed to ",
                        Strings.toString(_getPlayer(_table.players[i]).tableId)
                    )
                );
            }
        }

        // Put the last element in "tables" array to position of the target table

        if (_table.gameMode == GameMode.Beginner) {
            normalModeBeginnerTableIndexes.pop();
        } else if (_table.gameMode == GameMode.Intermediate) {
            normalModeIntermediateTableIndexes.pop();
        } else if (_table.gameMode == GameMode.Advanced) {
            normalModeAdvancedTableIndexes.pop();
        } else if (_table.gameMode == GameMode.Rank) {
            rankModeTableIndexes.pop();
        }

        uint256 oldTableId = tables.length - 1;

        console.log("Mostly done");

        // if this table is also the last element, just simply pop() and stop this process
        if (oldTableId == tableId) {
            tables.pop();
            console.log("Done!");

            return;
        }

        _table = tables[oldTableId];
        tables[tableId] = _table;
        _getPlayer(_table.players[0]).tableId = tableId;
        _getPlayer(_table.players[1]).tableId = tableId;

        emit UpdatedTableId(oldTableId, tableId);

        // then remove the last element/table
        tables.pop();
    }

    function startNewMatch(uint256 tableId) external joiningTable(tableId) {
        Table storage table = tables[tableId];

        if (
            (table.players[0] == address(0)) || (table.players[1] == address(0))
        ) {
            revert InvalidAction("Not enough players to start");
        }

        // if (tokenContract.balanceOf(table.players[0]) < table.stake) {
        //     revert InvalidAction("Player at first slot does not have enough tokens!");
        // }

        // if (tokenContract.balanceOf(table.players[1]) < table.stake) {
        //     revert InvalidAction("Player at second slot does not have enough tokens!");
        // }

        // if (tokenContract.allowance(table.players[0], address(this)) < table.stake) {
        //     revert InvalidAction("Player 0 did not approve enough tokens!");
        // }

        // if (tokenContract.allowance(table.players[1], address(this)) < table.stake) {
        //     revert InvalidAction("Player 1 did not approve enough tokens!");
        // }

        // tokenContract.transferFrom(_msgSender(), address(this), table.stake * 10 ** 18);
        // tokenContract.transferFrom(_msgSender(), address(this), table.stake * 10 ** 18);

        uint256 matchId = uint256(
            keccak256(abi.encodePacked(_msgSender(), block.timestamp, table.id))
        );
        table.matchId = matchId;

        // PlayerPiece[9][10] memory emptyBoard;
        Move[] memory emptyMoveList;
        PlayerPiece[9][10] memory board = _initBoard();
        console.log("Constructed board");
        Match memory newMatch = Match({
            id: matchId,
            gameMode: table.gameMode,
            players: table.players,
            stake: table.stake,
            timeControl: table.timeControl,
            startTimestamp: block.timestamp,
            endTimestamp: 0,
            matchStatus: MatchStatus.Started,
            board: board,
            matchResult: MatchResult(0, 2, MatchResultType.None, 10, 10),
            moves: emptyMoveList
        });
        console.log("Constructed match");

        matches.push(newMatch);
        matchIndexes[matchId] = matches.length - 1;

        emit NewMatchStarted(matchId, table.players);
    }

    function _initBoard()
        private
        view
        returns (PlayerPiece[9][10] memory board)
    {
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
        console.log("[_initBoard] Created 10 rows for board");

        // Init using random (keccak256... % 15)
        PlayerPiece[15]
            memory redTeam = _generateRandomlyOrderedNonGeneralPieceList(RED);
        console.log("[_initBoard] Generated order of red pieces");
        PlayerPiece[15]
            memory blackTeam = _generateRandomlyOrderedNonGeneralPieceList(
                BLACK
            );
        console.log("[_initBoard] Generated order of black pieces");

        // Assign to right positions
        uint8 pieceIndex = 0; // index of both redTeam & blackTeam

        // First row of each team
        for (uint8 col = 0; col < 9; col++ >= 0 && pieceIndex++ >= 0) {
            if (col == 4) {
                pieceIndex--;
                continue; // ignore position of General
            }

            firstRow[col] = redTeam[pieceIndex];
            tenthRow[col] = blackTeam[pieceIndex];
        }

        console.log("[_initBoard] Assigned pieces to first row of each side");
        // Third row of each team (containing only Cannons originally)
        thirdRow[1] = redTeam[pieceIndex];
        thirdRow[8 - 1] = redTeam[pieceIndex];
        pieceIndex++;
        eighthRow[1] = blackTeam[pieceIndex];
        eighthRow[8 - 1] = blackTeam[pieceIndex];
        pieceIndex++;
        console.log("[_initBoard] Assigned pieces to third row of each side");

        // Fourth row of each team (containing only Soldiers originally)
        for (uint8 col = 0; col < 9; col += 2) {
            fourthRow[col] = redTeam[pieceIndex];
            seventhRow[col] = blackTeam[pieceIndex];

            pieceIndex++;
        }
        console.log("[_initBoard] Assigned pieces to fouth row of each side");

        return board;
    }

    function _generateRandomlyOrderedNonGeneralPieceList(
        uint8 color
    ) private view returns (PlayerPiece[15] memory) {
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

    function verifyCheckmate(
        uint256 matchId,
        Move[] memory moves
    ) external payable joiningMatch(matchId) {
        Match storage _match = matches[matchIndexes[matchId]];
        uint8 playerIndex = (_match.players[0] == _msgSender()) ? 0 : 1;
        // If this value is kept throughout the for loop, the general piece had not been moved any time.
        Move memory finalMove = moves[moves.length - 1];
        Position memory defeatedGeneralPosition = finalMove.details.newPosition;

        uint32 fixedElo = 10;
        uint8 winnerIndex = (defeatedGeneralPosition.y <= 2)
            ? BLACK
            : RED;

        MatchResult memory matchResult = MatchResult(
            winnerIndex,
            playerIndex,
            MatchResultType.Checkmate,
            fixedElo,
            fixedElo
        );
        _match.moves = moves;
        _match.matchResult = matchResult;
        _match.matchStatus = MatchStatus.Ended;
        // _match.moves = moves;
        players[playerIndexes[_match.players[winnerIndex]]].elo += int32(
            fixedElo
        );
        players[playerIndexes[_match.players[1 - winnerIndex]]].elo -= int32(
            fixedElo
        );

        tables[_getPlayer(_msgSender()).tableId].matchId = 0;

        // TODO: implement token transfer

        emit MatchEnded(_match);
    }

    // function offerDraw(uint256 matchId) external joiningMatch(matchId) {
    //     Match storage _match = matches[matchIndexes[matchId]];
    //     uint8 playerIndex = (_match.players[0] == _msgSender()) ? 0 : 1;
    //     Vote[2] memory votes;

    //     drawVotes[matchId] = votes;
    //     votes[playerIndex] = Vote.Approve;

    //     emit OfferingDraw(matchId, _msgSender());
    // }

    // function responseDrawOffer(
    //     uint256 matchId,
    //     Vote vote,
    //     Move[] memory moves
    // ) external joiningMatch(matchId) {
    //     Match storage _match = matches[matchIndexes[matchId]];
    //     uint8 playerIndex = (_match.players[0] == _msgSender()) ? 0 : 1;
    //     // Vote[2] storage votes = d;
    //     drawVotes[matchId][playerIndex] = vote;

    //     if (vote == Vote.Approve) {
    //         MatchResult memory matchResult = MatchResult(
    //             2,
    //             1 - playerIndex,
    //             MatchResultType.OfferToDraw,
    //             0,
    //             0
    //         );
    //         _match.matchResult = matchResult;
    //         _match.matchStatus = MatchStatus.Ended;
    //         _match.moves = moves;

    //         tables[_getPlayer(_msgSender()).tableId].matchId = 0;

    //         // TODO: implement token transfer

    //         emit MatchEnded(_match);
    //         emit ApprovedDrawOffer(matchId, _msgSender()); // similar to event `MatchEnded` in this case
    //     } else if (vote == Vote.Decline) {
    //         emit DeclinedDrawOffer(matchId, _msgSender());
    //     }
    // }

    function resign(
        uint256 matchId,
        Move[] memory moves
    ) external payable joiningMatch(matchId) {
        _resign(matchId, moves);
    }

    function _resign(
        uint256 matchId,
        Move[] memory moves
    ) private joiningMatch(matchId) {
        uint32 fixedElo = 10;
        Match storage _match = matches[matchIndexes[matchId]];
        uint8 playerIndex = (_match.players[0] == _msgSender()) ? 0 : 1;
        uint8 winnerIndex = 1 - playerIndex;
        MatchResult memory matchResult = MatchResult(
            winnerIndex,
            playerIndex,
            MatchResultType.Resign,
            fixedElo,
            fixedElo
        );
        _match.matchResult = matchResult;
        _match.matchStatus = MatchStatus.Ended;
        _match.moves = moves;
        players[playerIndexes[_match.players[winnerIndex]]].elo += int32(
            fixedElo
        );
        players[playerIndexes[_match.players[1 - winnerIndex]]].elo -= int32(
            fixedElo
        );

        tables[_getPlayer(_msgSender()).tableId].matchId = 0;

        // TODO: implement token transfer

        emit MatchEnded(_match);
    }

    function resignAndExitTable(
        uint256 matchId,
        Move[] memory moves
    ) external payable joiningMatch(matchId) {
        console.log("Start resign function");
        _resign(matchId, moves);
        console.log("Start exitTable function");
        console.log(_getPlayer(_msgSender()).playerAddress);
        console.log(Strings.toString(_getPlayer(_msgSender()).tableId));
        _exitTable(_getPlayer(_msgSender()).tableId);
    }
}
