import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../services/multiplayer_service.dart';
import '../services/game_logger.dart';

/// Dedicated provider for multiplayer games
/// This handles all multiplayer game logic separately from single-player games
class MultiplayerGameProvider with ChangeNotifier {
  TrexGame? _game;
  bool _isLoading = false;
  String? _errorMessage;
  final GameLogger _logger = GameLogger();
  PlayerPosition? _humanPlayerPosition;
  MultiplayerService? _multiplayerService;
  StreamSubscription? _gameStateSubscription;
  
  // Getters
  TrexGame? get game => _game;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveGame => _game != null;
  PlayerPosition? get humanPlayerPosition => _humanPlayerPosition;
  bool get isHumanPlayerTurn => _game != null && _game!.currentPlayer == _humanPlayerPosition;
  
  Player? get currentUser => _game?.players.firstWhere(
    (player) => player.position == (_humanPlayerPosition ?? PlayerPosition.south),
    orElse: () => _game!.players.first,
  );

  /// Initialize multiplayer game with server's game state
  Future<void> initializeGame(Player humanPlayer, List<Player> aiPlayers, Map<String, dynamic> serverGameState, MultiplayerService multiplayerService) async {
    if (kDebugMode) {
      print('🌐 ===== INITIALIZE MULTIPLAYER GAME =====');
      print('🎮 Human player: "${humanPlayer.name}" (${humanPlayer.position.name})');
      print('🎮 AI players count: ${aiPlayers.length}');
      print('🎮 Server game state phase: ${serverGameState['phase']}');
      print('🎮 Server game state contract: ${serverGameState['currentContract']}');
      print('🌐 ==========================================');
    }
    
    _isLoading = true;
    _errorMessage = null;
    _humanPlayerPosition = humanPlayer.position;
    _multiplayerService = multiplayerService;
    notifyListeners();

    try {
      // Initialize logging system
      await _logger.initialize();
      
      // Create all players (human + AI)
      final allPlayers = <Player>[humanPlayer, ...aiPlayers];
      
      // Create game instance with server's first king
      final firstKingPosition = _parsePlayerPosition(serverGameState['currentKing'] ?? 'south');
      _game = TrexGame(players: allPlayers, firstKing: firstKingPosition);
      
      // Sync with server's game state
      _syncWithServerGameState(serverGameState);
      
      // Listen to game state updates from server
      _gameStateSubscription = _multiplayerService!.gameStateStream.listen((gameState) {
        if (kDebugMode) {
          print('🌐 Received game state update from server');
        }
        _handleServerGameStateUpdate(gameState.toJson());
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
      _game = null;
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

  /// Select contract (send to server)
  void selectContract(TrexContract contract) {
    if (_game == null || _game!.phase != GamePhase.contractSelection || _multiplayerService == null) return;
    
    if (!isHumanPlayerTurn) {
      if (kDebugMode) print('⚠️ Not human player\'s turn for contract selection');
      return;
    }
    
    try {
      if (kDebugMode) {
        print('🌐 Sending contract selection to server: ${contract.name}');
      }
      
      // Log the contract selection
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logContractSelection(contract, _game!.availableContracts, humanPlayer);
      }
      
      // Send to server - don't update local state, wait for server response
      _multiplayerService!.selectContract(contract.name);
      
    } catch (e) {
      _errorMessage = 'Error selecting contract: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Play card (send to server)
  void playCard(Card card) {
    if (_game == null || _game!.phase != GamePhase.playing || _multiplayerService == null) return;
    
    if (!isHumanPlayerTurn) {
      if (kDebugMode) print('⚠️ Not human player\'s turn to play card');
      return;
    }
    
    try {
      if (kDebugMode) {
        print('🌐 Sending card play to server: ${card.suit.name} ${card.rank.name}');
      }
      
      // Log the card play
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logCardPlay(card, humanPlayer, _game!);
      }
      
      // Send to server - don't update local state, wait for server response
      _multiplayerService!.playCard({
        'suit': card.suit.name,
        'rank': card.rank.name,
      });
      
    } catch (e) {
      _errorMessage = 'Error playing card: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Handle game state updates from server
  void _handleServerGameStateUpdate(Map<String, dynamic> serverGameState) {
    if (_game == null) return;
    
    try {
      if (kDebugMode) {
        print('🌐 ===== HANDLING SERVER GAME STATE UPDATE =====');
        print('🎯 Server phase: ${serverGameState['phase']}');
        print('🎯 Server contract: ${serverGameState['currentContract']}');
        print('🎯 Server current player: ${serverGameState['currentPlayer']}');
        print('🎯 Local game before sync: phase=${_game!.phase}, contract=${_game!.currentContract}');
      }
      
      // Sync with server's game state
      _syncWithServerGameState(serverGameState);
      
      if (kDebugMode) {
        print('🎯 Local game after sync: phase=${_game!.phase}, contract=${_game!.currentContract}');
        print('✅ Local game state synced with server');
        print('🌐 ===============================================');
      }
      
      notifyListeners();
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling server game state update: $e');
      }
    }
  }

  /// Sync local game state with server's game state
  void _syncWithServerGameState(Map<String, dynamic> serverGameState) {
    if (_game == null) return;
    
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
      
      // Sync current player
      final String? currentPlayer = serverGameState['currentPlayer'];
      if (currentPlayer != null) {
        _game!.currentPlayer = _parsePlayerPosition(currentPlayer);
      }
      
      // Sync current contract
      final String? currentContract = serverGameState['currentContract'];
      if (currentContract != null && currentContract != 'null') {
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

  /// Parse player position string to PlayerPosition enum
  PlayerPosition _parsePlayerPosition(String position) {
    switch (position.toLowerCase()) {
      case 'south':
        return PlayerPosition.south;
      case 'west':
        return PlayerPosition.west;
      case 'north':
        return PlayerPosition.north;
      case 'east':
        return PlayerPosition.east;
      default:
        if (kDebugMode) print('⚠️ Unknown player position: $position');
        return PlayerPosition.south;
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

  @override
  void dispose() {
    _gameStateSubscription?.cancel();
    super.dispose();
  }
}
