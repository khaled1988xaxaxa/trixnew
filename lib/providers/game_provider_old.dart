import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../services/ai_service.dart';
import '../services/lightweight_ai_adapter.dart';
import '../services/game_logger.dart';
import '../services/multiplayer_service.dart';

class GameProvider with ChangeNotifier {
  TrexGame? _game;
  bool _isLoading = false;
  String? _errorMessage;
  AIService? _aiService;
  final GameLogger _logger = GameLogger();
  DateTime? _actionStartTime; // Track thinking time
  PlayerPosition? _humanPlayerPosition; // Track which position is the human player
  bool _isMultiplayerGame = false; // Track if this is a multiplayer game
  MultiplayerService? _multiplayerService; // Reference to multiplayer service

  TrexGame? get game => _game;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveGame {
    if (kDebugMode) {
      print('🎮 hasActiveGame check: _game is null? ${_game == null}');
      if (_game != null) {
        print('   Game details: Phase=${_game!.phase.englishName}, ' 'Players=${_game!.players.length}, ' +
              'Current player=${_game!.currentPlayer.englishName}');
      }
    }
    // Only check for null game, not empty hands (empty hands are normal at end of rounds)
    return _game != null;
  }

  /// Get the human player position
  PlayerPosition? get humanPlayerPosition => _humanPlayerPosition;

  /// Check if the current player is the human player
  bool get isHumanPlayerTurn => _game != null && _game!.currentPlayer == _humanPlayerPosition;

  Player? get currentUser => _game?.players.firstWhere(
    (player) => player.position == (_humanPlayerPosition ?? PlayerPosition.south),
    orElse: () => _game!.players.first,
  );

  Future<void> startNewGame(Player humanPlayer, List<Player> aiPlayers) async {
    if (kDebugMode) {
      print('🎮 ===== START NEW GAME CALLED (with players) =====');
      print('🎮 Method signature: startNewGame(Player, List<Player>)');
      print('🎮 Human player: "${humanPlayer.name}" (${humanPlayer.position.name})');
      print('🎮 AI players count: ${aiPlayers.length}');
      for (int i = 0; i < aiPlayers.length; i++) {
        print('🎮   AI[$i]: "${aiPlayers[i].name}" (${aiPlayers[i].position.name})');
      }
      print('🎮 ================================================');
    }
    
    _isLoading = true;
    _errorMessage = null;
    _humanPlayerPosition = humanPlayer.position; // Store which position is the human player
    notifyListeners();

    try {
      // Initialize logging system
      await _logger.initialize();
      
      await reinitializeAIService();
      
      final players = [humanPlayer, ...aiPlayers];

      // Verify that we have 4 players total
      if (players.length != 4) {
        throw Exception('Invalid number of players: ${players.length}. Expected 4.');
      }
      
      // Check that all positions are assigned and unique
      final positionSet = players.map((p) => p.position).toSet();
      if (positionSet.length != 4) {
        throw Exception('Duplicate or missing player positions found. Positions: ${players.map((p) => p.position.name).join(', ')}');
      }
      
      // Verify all required positions are present
      final requiredPositions = {PlayerPosition.south, PlayerPosition.west, PlayerPosition.north, PlayerPosition.east};
      if (!positionSet.containsAll(requiredPositions)) {
        throw Exception('Missing required positions. Found: ${positionSet.map((p) => p.name).join(', ')}');
      }

      if (kDebugMode) {
        print('🎮 Players validated: ${players.map((p) => "${p.name} (${p.position.name})").join(', ')}');
      }

      _game = TrexGame(players: players, firstKing: PlayerPosition.south); // Temp king
      
      if (_game == null) {
        throw Exception('Failed to create game object.');
      }

      if (kDebugMode) {
        print('✅ Game object created successfully');
      }
      
      _game!.dealCards();
      if (kDebugMode) {
        print('✅ Cards dealt successfully');
      }
      
      _findFirstKing();
      _game!.startContractSelection();
      
      if (kDebugMode) {
        print('✅ Game setup complete. Phase: ${_game!.phase.englishName}, Current Player: ${_game!.currentPlayer.englishName}');
      }

      _isLoading = false;
      // This is the most critical notification. It tells the UI that the game is ready.
      notifyListeners(); 
      
      // This delay gives the UI a moment to react before bot actions start.
      await Future.delayed(const Duration(milliseconds: 100));
      
      // The check inside the method was causing a premature failure. 
      // The state will be validated by the UI that consumes this provider.
      _handleBotActions();

    } catch (e, s) {
      _isLoading = false;
      _game = null; // Explicitly nullify the game on error
      _errorMessage = 'Error creating game: ${e.toString()}';
      if (kDebugMode) {
        print('❌ ===== ERROR IN startNewGame =====');
        print('❌ Error: $e');
        print('❌ Stack Trace: $s');
        print('❌ =====================================');
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Initialize multiplayer game with server's game state
  Future<void> initializeMultiplayerGame(Player humanPlayer, List<Player> aiPlayers, Map<String, dynamic> serverGameState, MultiplayerService multiplayerService) async {
    if (kDebugMode) {
      print('🎮 ===== INITIALIZE MULTIPLAYER GAME =====');
      print('🎮 Human player: "${humanPlayer.name}" (${humanPlayer.position.name})');
      print('🎮 AI players count: ${aiPlayers.length}');
      print('🎮 Server game state phase: ${serverGameState['phase']}');
      print('🎮 Server game state contract: ${serverGameState['currentContract']}');
      print('🎮 ==========================================');
    }
    
    _isLoading = true;
    _errorMessage = null;
    _humanPlayerPosition = humanPlayer.position; // Store which position is the human player
    _isMultiplayerGame = true; // Mark as multiplayer game
    _multiplayerService = multiplayerService; // Store multiplayer service reference
    notifyListeners();

    try {
      // Initialize logging system
      await _logger.initialize();
      
      // Create all players (human + AI)
      final allPlayers = <Player>[humanPlayer, ...aiPlayers];
      
      // Create game instance with a temporary first king (will be synced from server)
      _game = TrexGame(players: allPlayers, firstKing: PlayerPosition.south);
      
      // Instead of dealing cards and starting fresh, sync with server's game state
      await _syncWithServerGameState(serverGameState);
      
      // Listen to game state updates from server
      _multiplayerService!.gameStateStream.listen((gameState) {
        if (kDebugMode) {
          print('🌐 Received game state update from server');
        }
        handleServerGameStateUpdate(gameState.toJson());
      });
      
      if (kDebugMode) {
        print('✅ Multiplayer game initialized successfully');
        print('🎯 Game phase: ${_game!.phase}');
        print('🎯 Current contract: ${_game!.currentContract}');
        print('🎯 Players: ${_game!.players.map((p) => '${p.name}(${p.position.name})').join(', ')}');
      }
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e, s) {
      _isLoading = false;
      _game = null; // Explicitly nullify the game on error
      _errorMessage = 'Error initializing multiplayer game: ${e.toString()}';
      if (kDebugMode) {
        print('❌ ===== ERROR IN initializeMultiplayerGame =====');
        print('❌ Error: $e');
        print('❌ Stack Trace: $s');
        print('❌ ===============================================');
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Sync local game state with server's game state
  Future<void> _syncWithServerGameState(Map<String, dynamic> serverGameState) async {
    if (_game == null) {
      throw Exception('Game instance is null');
    }
    
    try {
      // Sync game phase
      final String? phase = serverGameState['phase'];
      if (phase != null) {
        switch (phase) {
          case 'contractSelection':
            _game!.phase = GamePhase.contractSelection;
            break;
          case 'playing':
            _game!.phase = GamePhase.playing;
            break;
          case 'roundEnd':
            _game!.phase = GamePhase.roundEnd;
            break;
          case 'gameEnd':
            _game!.phase = GamePhase.gameEnd;
            break;
          default:
            if (kDebugMode) print('⚠️ Unknown game phase from server: $phase');
        }
      }
      
      // Sync current contract
      final String? currentContract = serverGameState['currentContract'];
      if (currentContract != null && currentContract != 'null') {
        // Convert string to TrexContract enum (handle both camelCase and PascalCase)
        switch (currentContract.toLowerCase()) {
          case 'kingofhearts':
          case 'king of hearts':
            _game!.currentContract = TrexContract.kingOfHearts;
            break;
          case 'trixnotricks':
          case 'trex':
            _game!.currentContract = TrexContract.trex;
            break;
          case 'diamonds':
            _game!.currentContract = TrexContract.diamonds;
            break;
          case 'hearts':
          case 'collections':
            _game!.currentContract = TrexContract.collections;
            break;
          case 'girls':
          case 'queens':
            _game!.currentContract = TrexContract.queens;
            break;
          default:
            if (kDebugMode) print('⚠️ Unknown contract from server: $currentContract');
        }
      }
      
      // Sync player hands if provided
      final Map<String, dynamic>? playerHands = serverGameState['playerHands']?.cast<String, dynamic>();
      if (playerHands != null) {
        for (final player in _game!.players) {
          final String positionKey = player.position.name;
          final List<dynamic>? handData = playerHands[positionKey]?.cast<dynamic>();
          if (handData != null) {
            // Clear existing hand and add new cards
            player.hand.clear();
            player.hand.addAll(handData.map((cardData) {
              if (cardData is Map<String, dynamic>) {
                return Card(
                  suit: _parseSuit(cardData['suit']),
                  rank: _parseRank(cardData['rank']),
                );
              }
              throw Exception('Invalid card data: $cardData');
            }));
          }
        }
      }
      
      if (kDebugMode) {
        print('✅ Game state synced with server');
        print('🎯 Phase: ${_game!.phase}');
        print('🎯 Contract: ${_game!.currentContract}');
        print('🎯 Players with hands: ${_game!.players.map((p) => '${p.name}(${p.hand.length} cards)').join(', ')}');
      }
      
    } catch (e) {
      if (kDebugMode) print('❌ Error syncing with server game state: $e');
      rethrow;
    }
  }

  /// Parse suit string to Suit enum
  Suit _parseSuit(dynamic suitData) {
    if (suitData is String) {
      switch (suitData.toLowerCase()) {
        case 'hearts':
          return Suit.hearts;
        case 'diamonds':
          return Suit.diamonds;
        case 'clubs':
          return Suit.clubs;
        case 'spades':
          return Suit.spades;
        default:
          throw Exception('Unknown suit: $suitData');
      }
    }
    throw Exception('Invalid suit data type: ${suitData.runtimeType}');
  }

  /// Parse rank string to Rank enum
  Rank _parseRank(dynamic rankData) {
    if (rankData is String) {
      switch (rankData.toLowerCase()) {
        case 'two':
          return Rank.two;
        case 'three':
          return Rank.three;
        case 'four':
          return Rank.four;
        case 'five':
          return Rank.five;
        case 'six':
          return Rank.six;
        case 'seven':
          return Rank.seven;
        case 'eight':
          return Rank.eight;
        case 'nine':
          return Rank.nine;
        case 'ten':
          return Rank.ten;
        case 'jack':
          return Rank.jack;
        case 'queen':
          return Rank.queen;
        case 'king':
          return Rank.king;
        case 'ace':
          return Rank.ace;
        default:
          throw Exception('Unknown rank: $rankData');
      }
    } else if (rankData is int) {
      // Handle numeric ranks
      switch (rankData) {
        case 2:
          return Rank.two;
        case 3:
          return Rank.three;
        case 4:
          return Rank.four;
        case 5:
          return Rank.five;
        case 6:
          return Rank.six;
        case 7:
          return Rank.seven;
        case 8:
          return Rank.eight;
        case 9:
          return Rank.nine;
        case 10:
          return Rank.ten;
        case 11:
          return Rank.jack;
        case 12:
          return Rank.queen;
        case 13:
          return Rank.king;
        case 14:
          return Rank.ace;
        default:
          throw Exception('Unknown numeric rank: $rankData');
      }
    }
    throw Exception('Invalid rank data type: ${rankData.runtimeType}');
  }

  /// Handle game state updates from multiplayer server
  Future<void> handleServerGameStateUpdate(Map<String, dynamic> serverGameState) async {
    if (_game == null || !_isMultiplayerGame) return;
    
    try {
      if (kDebugMode) {
        print('🌐 ===== HANDLING SERVER GAME STATE UPDATE =====');
        print('🎯 Server phase: ${serverGameState['phase']}');
        print('🎯 Server contract: ${serverGameState['currentContract']}');
        print('🎯 Server current player: ${serverGameState['currentPlayer']}');
        print('🎯 Local game before sync: phase=${_game!.phase}, contract=${_game!.currentContract}');
      }
      
      // Sync with server's game state
      await _syncWithServerGameState(serverGameState);
      
      if (kDebugMode) {
        print('🎯 Local game after sync: phase=${_game!.phase}, contract=${_game!.currentContract}');
        print('✅ Local game state synced with server');
        print('🌐 ===============================================');
      }
      
      notifyListeners();
      
      // Handle bot actions after state update
      _handleBotActions();
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling server game state update: $e');
      }
    }
  }

  void _findFirstKing() {
    if (_game == null) {
      if (kDebugMode) print('❌ Error: Game is null in _findFirstKing');
      return;
    }
    
    if (_game!.players.any((p) => p.hand.isEmpty)) {
      if (kDebugMode) {
        print('⚠️ Warning: Some players have empty hands');
      }
    }
    
    PlayerPosition? firstKing;
    Card? lowestSpade;
    
    for (Player player in _game!.players) {
      for (Card card in player.hand) {
        if (card.suit == Suit.spades) {
          if (lowestSpade == null || card.rank.value < lowestSpade.rank.value) {
            lowestSpade = card;
            firstKing = player.position;
          }
        }
      }
    }
    
    if (firstKing == null) {
      if (kDebugMode) print('⚠️ Warning: No spades found, using south as default king');
      firstKing = PlayerPosition.south;
    }
    
    _game!.currentKing = firstKing;
    _game!.currentPlayer = firstKing;
    
    if (kDebugMode) {
      print('👑 First king determined: ${_game!.currentKing.englishName}');
    }
  }

  void selectContract(TrexContract contract) {
    if (_game == null || _game!.phase != GamePhase.contractSelection) return;
    
    // Log thinking time if we were tracking it
    if (_actionStartTime != null) {
      final thinkingTime = DateTime.now().difference(_actionStartTime!);
      _logger.logThinkingTime('contract_selection', thinkingTime, {
        'available_contracts': _game!.availableContracts.map((c) => c.name).toList(),
        'selected_contract': contract.name,
      });
    }
    
    try {
      // Log the contract selection
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logContractSelection(contract, _game!.availableContracts, humanPlayer);
      }
      
      // If this is a multiplayer game, send the contract selection to the server
      if (_isMultiplayerGame && _multiplayerService != null) {
        if (kDebugMode) {
          print('🌐 Sending contract selection to server: ${contract.name}');
        }
        _multiplayerService!.selectContract(contract.name);
        // Don't update local state here - wait for server response
        return;
      }
      
      // For single player games, update local state immediately
      if (_game!.selectContract(contract)) {
        notifyListeners();
        _handleBotActions();
      }
    } catch (e) {
      _errorMessage = 'Error selecting contract: ${e.toString()}';
      notifyListeners();
    }
  }

  void playCard(Card card) {
    if (_game == null || _game!.phase != GamePhase.playing) return;
    
    // Log thinking time if we were tracking it
    if (_actionStartTime != null) {
      final thinkingTime = DateTime.now().difference(_actionStartTime!);
      final humanPlayer = currentUser;
      _logger.logThinkingTime('card_play', thinkingTime, {
        'played_card': card.toString(),
        'hand_size': humanPlayer?.hand.length ?? 0,
        'contract': _game!.currentContract?.name,
      });
    }
    
    try {
      // Log the card play before executing
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logCardPlay(card, humanPlayer, _game!);
      }
      
      if (_game!.playCard(_humanPlayerPosition!, card)) {
        notifyListeners();
        _handleBotActions();
      }
    } catch (e) {
      _errorMessage = 'Error playing card: ${e.toString()}';
      notifyListeners();
    }
  }

  void doubleKingOfHearts() {
    if (_game == null || _game!.currentContract != TrexContract.kingOfHearts) return;
    
    try {
      // Log the doubling decision
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logKingOfHeartsDoubling(true, humanPlayer, _game!);
      }
      
      if (_game!.doubleKingOfHearts()) {
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Error doubling king: ${e.toString()}';
      notifyListeners();
    }
  }

  void passTrexTurn() {
    if (_game == null || _game!.currentContract != TrexContract.trex) return;
    if (_game!.currentPlayer != _humanPlayerPosition) return;
    
    try {
      // Log the Trex pass decision
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logTrexPass(humanPlayer, _game!);
      }
      
      _game!.passTrexTurn();
      notifyListeners();
      _handleBotActions();
    } catch (e) {
      _errorMessage = 'Error passing turn: ${e.toString()}';
      notifyListeners();
    }
  }

  bool get canHumanPlayerPass {
    if (_game == null || _game!.currentContract != TrexContract.trex) return false;
    if (_game!.currentPlayer != _humanPlayerPosition) return false;
    final currentUser = this.currentUser;
    if (currentUser == null) return false;
    return !_game!.hasValidTrexMove(currentUser);
  }

  bool get shouldHighlightCards {
    if (_game == null) return false;
    if (_game!.phase != GamePhase.playing) return false;
    if (_game!.currentPlayer != _humanPlayerPosition) return false;
    // Only highlight cards during Trix contract to help players understand valid moves
    return _game!.currentContract == TrexContract.trex;
  }

  List<Card> getValidCardsForHuman() {
    if (_game == null || _game!.phase != GamePhase.playing) return [];
    if (_game!.currentPlayer != _humanPlayerPosition) return [];
    
    final currentUser = this.currentUser;
    if (currentUser == null) return [];
    
    if (_game!.currentContract == TrexContract.trex) {
      return currentUser.hand.where((card) => _game!.canPlayTrexCard(card)).toList();
    } else {
      return currentUser.hand.where((card) => _game!.isValidTrickPlay(currentUser, card)).toList();
    }
  }

  Future<void> _handleBotActions() async {
    if (_game == null) return;

    // First, check if the current player has any valid moves. If not, skip their turn.
    await _checkAndSkipTurnIfNeeded();

    if (_game == null) return; // Game might be null after state changes

    if (_game!.phase == GamePhase.trickComplete) {
      Future.delayed(const Duration(seconds: 1), () {
        if (_game != null) {
          if (kDebugMode) print('⏰ Completing trick after delay');
          _game!.completeTrick();
          notifyListeners();
          _handleBotActions();
        }
      });
      return;
    }

    if (_game!.phase == GamePhase.roundEnd || 
        _game!.phase == GamePhase.kingdomEnd || 
        _game!.phase == GamePhase.gameEnd) {
      if (kDebugMode) print('🏁 Game phase is ${_game!.phase.englishName} - stopping bot actions');
      return;
    }

    if (_game!.currentPlayer == _humanPlayerPosition) {
      if (kDebugMode) print('🎮 Human player turn (${_humanPlayerPosition?.englishName}) - waiting for user input');
      // Even for human, check if they are stuck, and if so, auto-pass.
      if (_game!.currentContract == TrexContract.trex && canHumanPlayerPass) {
        if (kDebugMode) print('🤖 Human has no valid Trex moves, auto-passing.');
        Future.delayed(const Duration(milliseconds: 500), () {
          passTrexTurn();
        });
      }
      return;
    }

    Future.delayed(const Duration(milliseconds: 800), () async {
      if (_game == null || _game!.currentPlayer == _humanPlayerPosition) return;
      
      try {
        if (kDebugMode) print('🤖 Bot check: Phase=${_game!.phase.englishName}, Player=${_game!.currentPlayer.englishName}');
        
        if (_game!.phase == GamePhase.contractSelection) {
          final botContract = await _calculateBotContract(_game!.currentPlayer);
          if (botContract != null) {
            if (kDebugMode) print('Bot ${_game!.currentPlayer.englishName} selecting: ${botContract.englishName}');
            _game!.selectContract(botContract);
            notifyListeners();
            _handleBotActions();
          } else {
            if (kDebugMode) print('Bot ${_game!.currentPlayer.englishName} passed contract selection');
            notifyListeners();
            _handleBotActions();
          }
        } else if (_game!.phase == GamePhase.playing) {
          final currentPlayerBefore = _game!.currentPlayer;
          final botCard = await _selectBotCard(_game!.currentPlayer);
          
          if (botCard != null) {
            if (kDebugMode) print('Bot ${_game!.currentPlayer.englishName} attempting to play: ${botCard.rank.englishName} ${botCard.suit.englishName}');
            
            // Debug: Check if the card is actually valid
            bool isCardValid = false;
            if (_game!.currentContract == TrexContract.trex) {
              isCardValid = _game!.canPlayTrexCard(botCard);
            } else {
              final player = _game!.getPlayerByPosition(_game!.currentPlayer);
              isCardValid = _game!.isValidTrickPlay(player, botCard);
            }
            
            if (kDebugMode) print('🔍 Card validity check: $isCardValid');
            
            bool gameStateChanged = _game!.playCard(_game!.currentPlayer, botCard);
            
            if (kDebugMode) print('🎮 Game state changed after play: $gameStateChanged');
            
            if (gameStateChanged) {
              notifyListeners();
              _handleBotActions();
            } else {
              if (kDebugMode) print('❌ Bot ${_game!.currentPlayer.englishName} card was rejected by game');
              // Force advance to next player to prevent infinite loop
              _game!.currentPlayer = _game!.currentPlayer.next;
              if (kDebugMode) print('🔄 Forced advancement to ${_game!.currentPlayer.englishName}');
              notifyListeners();
              _handleBotActions();
            }
          } else {
            // Bot passed turn - check if game state actually changed
            if (_game!.currentPlayer != currentPlayerBefore) {
              if (kDebugMode) print('Bot ${currentPlayerBefore.englishName} passed turn, now ${_game!.currentPlayer.englishName}\'s turn');
              notifyListeners();
              _handleBotActions();
            } else {
              // Game state didn't change - this might indicate a problem
              if (kDebugMode) print('⚠️ Bot ${_game!.currentPlayer.englishName} passed but game state unchanged - stopping to prevent infinite loop');
              
              // For Trex, check if all players are stuck
              if (_game!.currentContract == TrexContract.trex) {
                final allPlayersFinishedOrStuck = _game!.players.every((player) => 
                    player.hand.isEmpty || !_game!.hasValidTrexMove(player));
                
                if (allPlayersFinishedOrStuck) {
                  if (kDebugMode) print('🏁 All players finished or stuck in Trex - ending round');
                  
                  // Award points to players who are stuck with cards
                  _awardPointsToStuckPlayers();
                  
                  _game!.phase = GamePhase.roundEnd;
                  notifyListeners();
                  return;
                }
              }
              
              // For other contracts, similar check
              if (_game!.currentContract != TrexContract.trex) {
                final allPlayersHaveNoCards = _game!.players.every((player) => player.hand.isEmpty);
                if (allPlayersHaveNoCards) {
                  if (kDebugMode) print('🏁 All players finished - ending round');
                  _game!.phase = GamePhase.roundEnd;
                  notifyListeners();
                  return;
                }
              }
              
              // Force advance to break the loop
              if (kDebugMode) print('🔄 Force advancing to break infinite loop');
              _game!.currentPlayer = _game!.currentPlayer.next;
              notifyListeners();
              _handleBotActions();
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error in bot actions: $e');
        _errorMessage = 'Bot action error: ${e.toString()}';
        notifyListeners();
      }
    });
  }

  /// Checks if the current player has any valid moves. If not, it skips their turn.
  Future<void> _checkAndSkipTurnIfNeeded() async {
    if (_game == null || _game!.phase != GamePhase.playing) return;

    final currentPlayerObject = _game!.getPlayerByPosition(_game!.currentPlayer);
    if (currentPlayerObject.hand.isEmpty) {
      return; // Player has no cards, nothing to do.
    }
    
    // Special handling for human player - always give them a chance to play if they have cards
    if (_game!.currentPlayer == _humanPlayerPosition) {
      if (kDebugMode) {
        print('👤 Human player\'s turn - checking for valid moves');
      }
    }

    bool hasValidMoves;
    if (_game!.currentContract == TrexContract.trex) {
      hasValidMoves = _game!.hasValidTrexMove(currentPlayerObject);
      
      if (kDebugMode) {
        print('🧐 Checking valid Trex moves for ${currentPlayerObject.position.englishName}:');
        print('   Hand: ${currentPlayerObject.hand.map((c) => "${c.rank.englishName} of ${c.suit.englishName}").join(', ')}');
        print('   Has valid moves: $hasValidMoves');
        
        // Debug: Check each card individually
        for (var card in currentPlayerObject.hand) {
          bool canPlay = _game!.canPlayTrexCard(card);
          print('   ${card.rank.englishName} of ${card.suit.englishName} can be played: $canPlay');
        }
        
        // Debug: Check Jack cards specifically
        final jacks = currentPlayerObject.hand.where((c) => c.rank == Rank.jack).toList();
        if (jacks.isNotEmpty) {
          print('   Found ${jacks.length} Jack(s) in hand: ${jacks.map((c) => "${c.suit.englishName}").join(', ')}');
        }
      }
    } else {
      // For trick-based contracts, a player can always play a card if they have one.
      hasValidMoves = currentPlayerObject.hand.isNotEmpty;
    }

    if (!hasValidMoves) {
      if (kDebugMode) {
        print('🤖 Player ${currentPlayerObject.position.englishName} has no valid moves. Skipping turn.');
      }

      // This logic is primarily for the Trex contract, where a player can be forced to pass.
      if (_game!.currentContract == TrexContract.trex) {
        // Double-check for human player to make sure they don't have any Jacks
        if (currentPlayerObject.position == _humanPlayerPosition) {
          final hasJack = currentPlayerObject.hand.any((card) => card.rank == Rank.jack);
          if (hasJack) {
            if (kDebugMode) {
              print('⚠️ Human player has a Jack but system thinks they have no valid moves!');
              print('   Not skipping their turn to allow them to play the Jack.');
            }
            return; // Don't skip human player's turn if they have a Jack
          }
          
          // For human player, confirm they have no valid moves before skipping
          if (kDebugMode) {
            print('🔍 Double-checking human player has no valid Trex moves:');
            for (var card in currentPlayerObject.hand) {
              print('   Checking ${card.rank.englishName} of ${card.suit.englishName}: ${_game!.canPlayTrexCard(card)}');
            }
          }
        }
        
        _game!.passTrexTurn();
        notifyListeners();

        // Give a moment for the UI to update before checking the next player.
        await Future.delayed(const Duration(milliseconds: 100));

        // Recursively call to handle the next player, who might also need to be skipped.
        await _handleBotActions();
      }
    }
  }

  Future<TrexContract?> _calculateBotContract(PlayerPosition position) async {
    final availableContracts = _game!.availableContracts;
    if (availableContracts.isEmpty) return null;

    if (_aiService != null) {
      try {
        final aiContract = await _aiService!.selectContractWithFastFallback(
          botPosition: position,
          game: _game!,
          availableContracts: availableContracts,
        );
        if (aiContract != null && availableContracts.contains(aiContract)) {
          return aiContract;
        }
      } catch (e) {
        if (kDebugMode) print('❌ AI contract selection error: $e');
      }
    }
    
    final preferences = _calculateContractPreferences(_game!.getPlayerByPosition(position));
    return preferences.first;
  }

  Future<Card?> _selectBotCard(PlayerPosition position) async {
    final player = _game!.getPlayerByPosition(position);
    if (player.hand.isEmpty) return null;

    if (_aiService != null) {
      try {
        List<Card> validCards;
        if (_game!.currentContract == TrexContract.trex) {
          validCards = player.hand.where((card) => _game!.canPlayTrexCard(card)).toList();
        } else {
          validCards = player.hand.where((card) => _game!.isValidTrickPlay(player, card)).toList();
        }

        if (validCards.isNotEmpty) {
          final aiCard = await _aiService!.selectCardWithFastFallback(
            botPosition: position,
            game: _game!,
            hand: player.hand,
            validCards: validCards,
          );
          if (aiCard != null && validCards.contains(aiCard)) {
            return aiCard;
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ AI card selection error: $e');
      }
    }

    if (_game!.currentContract == TrexContract.trex) {
      final selectedCard = _selectTrexCard(player);
      if (selectedCard == null) {
        // Player has no valid moves, pass the turn
        if (kDebugMode) print('Bot ${player.position.englishName} passing Trex turn');
        _game!.passTrexTurn();
      }
      return selectedCard;
    } else {
      // For trick-based contracts
      final selectedCard = _selectTrickCard(player);
      if (selectedCard == null) {
        // This should rarely happen in trick-based games
        // If no card is valid, just play the first card (emergency fallback)
        if (player.hand.isNotEmpty) {
          if (kDebugMode) print('Bot ${player.position.englishName} emergency fallback - playing first card');
          return player.hand.first;
        } else {
          if (kDebugMode) print('Bot ${player.position.englishName} has no cards left');
          return null;
        }
      }
      return selectedCard;
    }
  }

  Card? _selectTrexCard(Player player) {
    final validMoves = player.hand.where((card) => _game!.canPlayTrexCard(card)).toList();
    if (validMoves.isEmpty) {
      // Player has no valid Trex moves, will pass the turn in the calling method
      if (kDebugMode) print('Player ${player.position.englishName} has no valid Trex moves');
      return null;
    }
    validMoves.sort((a, b) => b.rank.value.compareTo(a.rank.value));
    return validMoves.first;
  }

  Card? _selectTrickCard(Player player) {
    final allCards = player.hand;
    final validCards = allCards.where((card) => _game!.isValidTrickPlay(player, card)).toList();
    
    if (kDebugMode) {
      print('🎯 Selecting trick card for ${player.position.englishName}:');
      print('   Hand size: ${allCards.length}');
      print('   Valid cards: ${validCards.length}');
      print('   All cards: ${allCards.map((c) => '${c.rank.englishName} ${c.suit.englishName}').join(', ')}');
      if (validCards.isNotEmpty) {
        print('   Valid cards: ${validCards.map((c) => '${c.rank.englishName} ${c.suit.englishName}').join(', ')}');
      }
      if (_game!.currentTrick != null && _game!.currentTrick!.cards.isNotEmpty) {
        final leadCard = _game!.currentTrick!.cards.values.first;
        print('   Lead card: ${leadCard.rank.englishName} ${leadCard.suit.englishName}');
        print('   Has lead suit: ${allCards.any((c) => c.suit == leadCard.suit)}');
      }
    }
    
    if (validCards.isEmpty) {
      // Player has no valid cards for trick play - this should be very rare
      if (kDebugMode) {
        print('⚠️ Player ${player.position.englishName} has no valid cards for trick play');
        print('   This suggests a game logic issue - in trick play, a player should always be able to play some card');
      }
      return null;
    }

    Card selectedCard;
    switch (_game!.currentContract) {
      case TrexContract.kingOfHearts:
        selectedCard = _selectForKingOfHearts(validCards, player);
        break;
      case TrexContract.queens:
        selectedCard = _selectForQueens(validCards, player);
        break;
      case TrexContract.diamonds:
        selectedCard = _selectForDiamonds(validCards, player);
        break;
      case TrexContract.collections:
        selectedCard = _selectForCollections(validCards, player);
        break;
      default:
        selectedCard = validCards.first;
        break;
    }
    
    // Double-check that the selected card is actually valid
    if (!_game!.isValidTrickPlay(player, selectedCard)) {
      if (kDebugMode) print('❌ Selected card ${selectedCard.rank.englishName} ${selectedCard.suit.englishName} is not valid! Using first valid card instead.');
      selectedCard = validCards.first;
    }
    
    if (kDebugMode) print('✅ Selected card: ${selectedCard.rank.englishName} ${selectedCard.suit.englishName}');
    return selectedCard;
  }

  Card _selectForKingOfHearts(List<Card> validCards, Player player) {
    if (kDebugMode) {
      print('🛡️ === KING OF HEARTS PROTECTION SYSTEM ===');
      print('🃏 Valid cards: ${validCards.map((c) => "${c.rank.englishName} ${c.suit.englishName}").join(', ')}');
      print('👑 Has King of Hearts: ${validCards.any((card) => card.isKingOfHearts)}');
      print('🔢 Number of options: ${validCards.length}');
    }
    
    // Check if player has King of Hearts in their hand (not just in valid cards)
    final playerHand = player.hand;
    final hasKingOfHeartsInHand = playerHand.any((card) => card.isKingOfHearts);
    final kingOfHearts = validCards.firstWhere((c) => c.isKingOfHearts, orElse: () => Card(suit: Suit.clubs, rank: Rank.two));
    
    // STRATEGIC OPPORTUNITY: Check if we can safely discard King of Hearts
    if (hasKingOfHeartsInHand && kingOfHearts.isKingOfHearts) {
      // Check if we're following suit or can discard any card
      bool isFollowingSuit = false;
      if (_game!.currentTrick != null && _game!.currentTrick!.cards.isNotEmpty) {
        final leadCard = _game!.currentTrick!.cards.values.first;
        isFollowingSuit = playerHand.any((c) => c.suit == leadCard.suit);
        
        if (!isFollowingSuit) {
          // 🎯 GOLDEN OPPORTUNITY: We can discard any card - GET RID OF KING OF HEARTS!
          if (kDebugMode) {
            print('🎯 STRATEGIC DISCARD OPPORTUNITY DETECTED!');
            print('💡 Not following suit - can discard any card');
            print('👑 King of Hearts available to discard safely');
            print('🗑️ DISCARDING King of Hearts to avoid future -75 penalty');
          }
          return kingOfHearts;
        }
      }
    }
    
    // CRITICAL BUG FIX: NEVER choose King of Hearts if other options exist when following suit
    if (kingOfHearts.isKingOfHearts && validCards.length > 1) {
      if (kDebugMode) {
        print('🚨 CRITICAL BUG PREVENTION: King of Hearts found with other options!');
        print('🛡️ EMERGENCY OVERRIDE: Removing King of Hearts from consideration');
        print('💰 Avoiding -75 point penalty');
      }
      
      // Remove King of Hearts from options
      List<Card> safeCards = validCards.where((card) => !card.isKingOfHearts).toList();
      
      if (safeCards.isNotEmpty) {
        // Choose the lowest rank safe card to minimize risk
        safeCards.sort((a, b) => a.rank.value.compareTo(b.rank.value));
        Card safeChoice = safeCards.first;
        
        if (kDebugMode) {
          print('✅ Emergency override successful!');
          print('🔄 Avoided: King of Hearts (-75 points)');
          print('🛡️ Chose instead: ${safeChoice.rank.englishName} ${safeChoice.suit.englishName}');
        }
        
        return safeChoice;
      }
    }
    
    // If forced to play King of Hearts (only option), accept it
    if (validCards.length == 1 && kingOfHearts.isKingOfHearts) {
      if (kDebugMode) {
        print('👑 Forced to play King of Hearts (only card available)');
        print('✅ This is acceptable - no other choice');
      }
      return kingOfHearts;
    }
    
    // Default: choose lowest rank card
    validCards.sort((a, b) => a.rank.value.compareTo(b.rank.value));
    Card defaultChoice = validCards.first;
    
    if (kDebugMode) {
      print('✅ Default choice: ${defaultChoice.rank.englishName} ${defaultChoice.suit.englishName}');
    }
    
    return defaultChoice;
  }

  Card _selectForQueens(List<Card> validCards, Player player) {
    validCards.sort((a, b) => a.rank.value.compareTo(b.rank.value));
    return validCards.first;
  }

  Card _selectForDiamonds(List<Card> validCards, Player player) {
    validCards.sort((a, b) => a.rank.value.compareTo(b.rank.value));
    return validCards.first;
  }

  Card _selectForCollections(List<Card> validCards, Player player) {
    validCards.sort((a, b) => a.rank.value.compareTo(b.rank.value));
    return validCards.first;
  }

  List<TrexContract> _calculateContractPreferences(Player player) {
    final handAnalysis = _analyzeHand(player.hand);
    final preferences = <TrexContract, int>{};

    for (var contract in _game!.availableContracts) {
      var score = 0;
      switch (contract) {
        case TrexContract.kingOfHearts:
          score += (handAnalysis['hasKingOfHearts'] as bool) ? -100 : 50;
          score += ((handAnalysis['highSpades'] as num) * 10).toInt();
          break;
        case TrexContract.queens:
          score -= ((handAnalysis['queensCount'] as num) * 25).toInt();
          break;
        case TrexContract.diamonds:
          score -= ((handAnalysis['diamondCount'] as num) * 10).toInt();
          break;
        case TrexContract.collections:
          score -= ((13 - (handAnalysis['highCards'] as num)) * 10).toInt();
          break;
        case TrexContract.trex:
          score += ((handAnalysis['lowCards'] as num) * 10).toInt();
          score -= ((handAnalysis['highCards'] as num) * 5).toInt();
          break;
      }
      preferences[contract] = score;
    }

    final sortedPreferences = preferences.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedPreferences.map((e) => e.key).toList();
  }

  Map<String, dynamic> _analyzeHand(List<Card> hand) {
    return {
      'hasKingOfHearts': hand.any((c) => c.isKingOfHearts),
      'queensCount': hand.where((c) => c.rank == Rank.queen).length,
      'diamondCount': hand.where((c) => c.suit == Suit.diamonds).length,
      'highCards': hand.where((c) => c.rank.value >= Rank.jack.value).length,
      'lowCards': hand.where((c) => c.rank.value <= Rank.six.value).length,
      'highSpades': hand.where((c) => c.suit == Suit.spades && c.rank.value >= Rank.jack.value).length,
    };
  }

  void resetGame() {
    // Log game end if there was an active game
    if (_game != null) {
      _logGameEnd();
    }
    
    _game = null;
    _isLoading = false;
    _errorMessage = null;
    _actionStartTime = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _aiService?.dispose();
    _logger.dispose();
    super.dispose();
  }

  Future<void> reinitializeAIService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('gemini_api_key');
      final useLightweightAI = prefs.getBool('use_lightweight_ai') ?? false;
      
      if (useLightweightAI) {
        // Use lightweight AI for testing
        _aiService = LightweightAIAdapter();
        if (kDebugMode) print('✅ Lightweight AI Service initialized for testing.');
      } else if (apiKey != null && apiKey.isNotEmpty) {
        _aiService = AIService(apiKey: apiKey);
        if (kDebugMode) print('✅ Full AI Service reinitialized successfully.');
      } else {
        _aiService = null;
        if (kDebugMode) print('⚠️ AI Service not initialized (no API key).');
      }
    } catch (e) {
      _aiService = null;
      if (kDebugMode) print('❌ Error reinitializing AI Service: $e');
    }
    notifyListeners();
  }

  bool get isAIServiceAvailable => _aiService != null;

  String get aiServiceStatus {
    if (_aiService == null) return 'Not Configured';
    return 'Active (${_aiService!.providerName})';
  }
  
  // Toggle between full AI and lightweight AI
  Future<void> setLightweightAIMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_lightweight_ai', enabled);
    await reinitializeAIService();
    if (kDebugMode) {
      print('🤖 AI Mode: ${enabled ? 'Lightweight (Testing)' : 'Full AI'}');
    }
  }

  bool get isLightweightAIMode {
    // This is a sync getter, so we'll check the AI service type
    return _aiService?.providerName.contains('Lightweight') ?? false;
  }
  
  Future<Map<String, dynamic>> testAIConnection() async {
    if (_aiService == null) {
      return {
        'success': false,
        'error': 'No AI service configured',
      };
    }
    return await _aiService!.testConnectionWithDebug();
  }

  Future<String> debugGameState() async {
    if (_game == null) return 'No active game.';

    final buffer = StringBuffer();
    buffer.writeln('--- GAME STATE DEBUG ---');
    buffer.writeln('Phase: ${_game!.phase.englishName}');
    buffer.writeln('Current Player: ${_game!.currentPlayer.englishName}');
    buffer.writeln('Current King: ${_game!.currentKing.englishName}');
    buffer.writeln('Contract: ${_game!.currentContract?.englishName ?? 'None'}');
    buffer.writeln('Players:');
    for (final player in _game!.players) {
      buffer.writeln('  - ${player.name} (${player.position.englishName}): ${player.hand.length} cards, Score: ${player.score}');
    }
    buffer.writeln('------------------------');
    return buffer.toString();
  }

  // Logging-related methods
  void startThinkingTimer() {
    _actionStartTime = DateTime.now();
  }

  void resetThinkingTimer() {
    _actionStartTime = null;
  }

  // Called when game ends to log final results
  void _logGameEnd() {
    if (_game != null) {
      _logger.logGameEnd(_game!);
    }
  }

  // Award points to players who are stuck with cards in Trex
  void _awardPointsToStuckPlayers() {
    if (_game == null || _game!.currentContract != TrexContract.trex) return;
    
    // Count how many players have already finished (empty hand)
    int finishedCount = _game!.players.where((p) => p.hand.isEmpty).length;
    
    // If 3 players have already finished, just award 50 points to the last player
    if (finishedCount == 3) {
      final lastPlayer = _game!.players.firstWhere((p) => p.hand.isNotEmpty);
      lastPlayer.score += 50;
      if (kDebugMode) print('👍 ${lastPlayer.position.englishName} awarded 50 points as the last player with cards');
      return;
    }
    
    // Award points to players who are stuck (have cards but no valid moves)
    for (Player player in _game!.players) {
      // Skip players who have already finished - they've already received their points
      if (player.hand.isEmpty) continue;
      
      // This player is stuck with cards
      if (!_game!.hasValidTrexMove(player)) {
        // Determine their "finishing position" based on already finished players
        finishedCount++;
        
        // Award points based on this finishing position
        switch (finishedCount) {
          case 1: // Should not happen, but handle it anyway
            player.score += 200;
            if (kDebugMode) print('🏆 ${player.position.englishName} awarded 200 points as stuck 1st player');
            break;
          case 2:
            player.score += 150;
            if (kDebugMode) print('🥈 ${player.position.englishName} awarded 150 points as stuck 2nd player');
            break;
          case 3:
            player.score += 100;
            if (kDebugMode) print('🥉 ${player.position.englishName} awarded 100 points as stuck 3rd player');
            break;
          case 4:
            player.score += 50;
            if (kDebugMode) print('👍 ${player.position.englishName} awarded 50 points as stuck 4th player');
            break;
        }
      }
    }
  }

  // Logging system access methods
  bool get isLoggingEnabled => _logger.isEnabled;

  Future<void> setLoggingEnabled(bool enabled) async {
    await _logger.setEnabled(enabled);
    notifyListeners();
  }

  Future<String> getLogsDirectory() async {
    return await _logger.getLogsDirectory();
  }

  Future<File?> exportTrainingData() async {
    return await _logger.exportLogsForTraining();
  }
}