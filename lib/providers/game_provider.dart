import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/card.dart';

/// Unified game provider that delegates to either single-player or multiplayer provider
class GameProvider with ChangeNotifier {
  bool _isMultiplayer = false;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _aiMoveTimer;
  
  // Game state
  TrexGame? _currentGame;
  Player? _currentUser;
  List<Player> _allPlayers = [];
  dynamic _multiplayerService; // Store multiplayer service for AI moves
  
  // Basic getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveGame => _currentGame != null; // Now properly implemented
  bool get isHumanPlayerTurn {
    if (!hasActiveGame || _currentUser == null) {
      if (kDebugMode) print('🔍 isHumanPlayerTurn: No active game or user - returning false');
      return false;
    }
    
    // In contract selection phase, check if current king is the human player
    if (_currentGame!.phase == GamePhase.contractSelection) {
      final result = _currentGame!.currentKing == _currentUser!.position;
      if (kDebugMode) {
        print('🔍 isHumanPlayerTurn: Contract selection phase');
        print('   - Current king: ${_currentGame!.currentKing}');
        print('   - Human position: ${_currentUser!.position}');
        print('   - Result: $result');
      }
      return result;
    }
    
    // In playing phase, check if current player is the human player
    if (_currentGame!.phase == GamePhase.playing) {
      final result = _currentGame!.currentPlayer == _currentUser!.position;
      if (kDebugMode) {
        print('🔍 isHumanPlayerTurn: Playing phase');
        print('   - Current player: ${_currentGame!.currentPlayer}');
        print('   - Human position: ${_currentUser!.position}');
        print('   - Result: $result');
      }
      return result;
    }
    
    if (kDebugMode) print('🔍 isHumanPlayerTurn: Unknown phase - returning false');
    return false;
  }

  // Force a UI update to check the getter
  void debugCheckTurn() {
    if (kDebugMode) {
      print('🔍 DEBUG: Manually checking isHumanPlayerTurn...');
      print('🔍 DEBUG: isHumanPlayerTurn = $isHumanPlayerTurn');
    }
    notifyListeners();
  }
  bool get isMultiplayerGame => _isMultiplayer;
  bool get shouldHighlightCards => hasActiveGame && isHumanPlayerTurn;
  bool get canHumanPlayerPass => hasActiveGame && isHumanPlayerTurn;
  bool get isLoggingEnabled => false; // TODO: Implement logging
  bool get isLightweightAIMode => false; // TODO: Implement AI mode detection
  
  /// Check if the current king/player is an AI
  bool get isCurrentPlayerAI {
    if (!hasActiveGame) return false;
    
    PlayerPosition? targetPosition;
    
    // In contract selection phase, check current king
    if (_currentGame!.phase == GamePhase.contractSelection) {
      targetPosition = _currentGame!.currentKing;
    } else if (_currentGame!.phase == GamePhase.playing) {
      targetPosition = _currentGame!.currentPlayer;
    }
    
    if (targetPosition == null) return false;
    
    // Check if this position belongs to an AI player
    final playerAtPosition = getPlayerByPosition(targetPosition);
    return playerAtPosition?.id.startsWith('ai_') ?? false;
  }
  
  /// Get player by position
  Player? getPlayerByPosition(PlayerPosition position) {
    if (kDebugMode) {
      print('🔍 getPlayerByPosition called for: $position');
      print('🔍 Available players:');
      for (var player in _allPlayers) {
        print('   - ${player.name}: ${player.position}');
      }
    }
    
    try {
      return _allPlayers.firstWhere((player) => player.position == position);
    } catch (e) {
      if (kDebugMode) print('🔍 No player found at position $position');
      return null;
    }
  }
  
  // Game object
  TrexGame? get game => _currentGame;
  
  // Current user object
  Player? get currentUser => _currentUser;
  dynamic get humanPlayerPosition => null; // TODO: Implement
  
  List<Card> getValidCardsForHuman() {
    if (_currentUser == null) return [];
    return _currentUser!.hand; // Return all cards for now - you can add validation logic later
  }
  
  void passTrexTurn() {
    if (kDebugMode) print('🎮 Pass Trex turn not implemented yet');
  }
  
  void doubleKingOfHearts() {
    if (kDebugMode) print('🎮 Double King of Hearts not implemented yet');
  }
  
  Future<void> setLoggingEnabled(bool enabled) async {
    if (kDebugMode) print('🎮 Set logging enabled: $enabled');
  }
  
  Future<String?> exportTrainingData() async {
    if (kDebugMode) print('🎮 Export training data not implemented yet');
    return null;
  }
  
  Future<String?> getLogsDirectory() async {
    if (kDebugMode) print('🎮 Get logs directory not implemented yet');
    return null;
  }
  
  Future<void> reinitializeAIService() async {
    if (kDebugMode) print('🎮 Reinitialize AI service not implemented yet');
  }
  
  Future<Map<String, dynamic>> testAIConnection() async {
    if (kDebugMode) print('🎮 Test AI connection not implemented yet');
    return {'success': false, 'message': 'Not implemented'};
  }

  /// UI integration helpers used by logging-aware widgets
  void startThinkingTimer() {
    if (kDebugMode) print('⏱️ startThinkingTimer called');
  }

  void resetThinkingTimer() {
    if (kDebugMode) print('⏱️ resetThinkingTimer called');
  }

  /// Initialize single-player game
  Future<void> startNewGame(Player humanPlayer, List<Player> aiPlayers) async {
    _isMultiplayer = false;
    if (kDebugMode) print('🎮 Single-player game initialization not implemented yet');
    notifyListeners();
  }

  /// Initialize multiplayer game
  Future<void> initializeMultiplayerGame(dynamic humanPlayer, List<dynamic> aiPlayers, Map<String, dynamic> serverGameState, dynamic multiplayerService) async {
    if (kDebugMode) {
      print('🎮 ===== INITIALIZING MULTIPLAYER GAME =====');
      print('🎮 Human player: $humanPlayer');
      print('🎮 AI players: ${aiPlayers.length}');
      print('🎮 Server game state: $serverGameState');
      print('🎮 ==========================================');
    }
    
    _isLoading = true;
    _errorMessage = null;
    _multiplayerService = multiplayerService; // Store for AI moves
    notifyListeners();
    
    try {
      _isMultiplayer = true;
      
      // Create Player objects from server data with correct positions and hands
      List<Player> gamePlayersList = [];
      
      // Helper function to parse suit from server data
      Suit parseSuit(String suitStr) {
        switch (suitStr.toLowerCase()) {
          case 'hearts': return Suit.hearts;
          case 'diamonds': return Suit.diamonds;
          case 'clubs': return Suit.clubs;
          case 'spades': return Suit.spades;
          default: return Suit.hearts;
        }
      }
      
      // Helper function to parse rank from server data
      Rank parseRank(String rankStr) {
        switch (rankStr.toLowerCase()) {
          case 'ace': return Rank.ace;
          case 'two': return Rank.two;
          case 'three': return Rank.three;
          case 'four': return Rank.four;
          case 'five': return Rank.five;
          case 'six': return Rank.six;
          case 'seven': return Rank.seven;
          case 'eight': return Rank.eight;
          case 'nine': return Rank.nine;
          case 'ten': return Rank.ten;
          case 'jack': return Rank.jack;
          case 'queen': return Rank.queen;
          case 'king': return Rank.king;
          default: return Rank.ace;
        }
      }
      
      // Helper function to get hand for a position from server game state
      List<Card> getHandForPosition(PlayerPosition position) {
        if (serverGameState.containsKey('playerHands')) {
          final playerHands = serverGameState['playerHands'] as Map<String, dynamic>;
          final positionKey = position.toString().split('.').last; // Convert PlayerPosition.south to 'south'
          if (playerHands.containsKey(positionKey)) {
            final handData = playerHands[positionKey] as List<dynamic>;
            return handData.map((cardData) {
              final cardMap = cardData as Map<String, dynamic>;
              return Card(
                suit: parseSuit(cardMap['suit']),
                rank: parseRank(cardMap['rank']),
              );
            }).toList();
          }
        }
        return [];
      }
      
      // Add human player with correct position and hand
      if (humanPlayer != null) {
        final position = humanPlayer.position; // Use the position already set on the Player object
        final humanPlayerData = Player(
          id: humanPlayer.id,
          name: humanPlayer.name,
          position: position,
          hand: getHandForPosition(position),
          isBot: false,
        );
        gamePlayersList.add(humanPlayerData);
        _currentUser = humanPlayerData;
      }
      
      // Add AI players with correct positions and hands
      for (var aiPlayer in aiPlayers) {
        final position = aiPlayer.position; // Use the position already set on the Player object
        final aiPlayerData = Player(
          id: aiPlayer.id,
          name: aiPlayer.name,
          position: position,
          hand: getHandForPosition(position),
          isBot: true,
        );
        gamePlayersList.add(aiPlayerData);
      }
      
      _allPlayers = gamePlayersList;
      
      // Debug: Print all players with their positions
      if (kDebugMode) {
        print('🎮 Created players:');
        for (var player in gamePlayersList) {
          print('   - ${player.name}: ${player.position} (${player.hand.length} cards)');
        }
      }
      
      // Create TrexGame with the players
      _currentGame = TrexGame(
        players: _allPlayers,
        firstKing: PlayerPosition.south, // Default, will be updated from server state
      );
      
      // Debug: Verify game players have correct positions
      if (kDebugMode) {
        print('🎮 Game players after TrexGame creation:');
        for (var player in _currentGame!.players) {
          print('   - ${player.name}: ${player.position} (${player.hand.length} cards)');
        }
      }
      
      // Update game state from server
      if (serverGameState.containsKey('phase')) {
        final phaseString = serverGameState['phase'];
        if (phaseString == 'contractSelection') {
          _currentGame!.phase = GamePhase.contractSelection;
        } else if (phaseString == 'playing') {
          _currentGame!.phase = GamePhase.playing;
        }
      }
      
      // Update current king from server state
      if (serverGameState.containsKey('currentKing')) {
        final currentKingStr = serverGameState['currentKing'].toString().toLowerCase();
        switch (currentKingStr) {
          case 'north': _currentGame!.currentKing = PlayerPosition.north; break;
          case 'south': _currentGame!.currentKing = PlayerPosition.south; break;
          case 'east': _currentGame!.currentKing = PlayerPosition.east; break;
          case 'west': _currentGame!.currentKing = PlayerPosition.west; break;
        }
      }
      
      // Update current player from server state
      if (serverGameState.containsKey('currentPlayer')) {
        final currentPlayerStr = serverGameState['currentPlayer'].toString().toLowerCase();
        switch (currentPlayerStr) {
          case 'north': _currentGame!.currentPlayer = PlayerPosition.north; break;
          case 'south': _currentGame!.currentPlayer = PlayerPosition.south; break;
          case 'east': _currentGame!.currentPlayer = PlayerPosition.east; break;
          case 'west': _currentGame!.currentPlayer = PlayerPosition.west; break;
        }
      }
      
      if (serverGameState.containsKey('round')) {
        _currentGame!.round = serverGameState['round'] ?? 1;
      }
      
      if (serverGameState.containsKey('kingdom')) {
        _currentGame!.kingdom = serverGameState['kingdom'] ?? 1;
      }
      
      _isLoading = false;
      
      if (kDebugMode) {
        print('✅ Multiplayer game initialized successfully!');
        print('🎮 Game has active game: $hasActiveGame');
        print('🎮 Game phase: ${_currentGame!.phase.arabicName}');
        print('🎮 Current king: ${_currentGame!.currentKing}');
        print('🎮 Current player: ${_currentGame!.currentPlayer}');
        print('🎮 Human player position: ${_currentUser?.position}');
        print('🎮 Is human player turn: $isHumanPlayerTurn');
      }
      
      // Force a UI update and debug check
      debugCheckTurn();
      
      // Schedule AI move if it's AI player's turn
      _scheduleAIMovesIfNeeded();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to initialize multiplayer game: $e';
      if (kDebugMode) print('❌ Multiplayer game initialization failed: $e');
      notifyListeners();
    }
  }

  /// Select contract
  void selectContract(dynamic contract) {
    if (kDebugMode) print('🎮 Contract selection: $contract (single player mode)');
    // This is used for single player mode fallback
  }

  /// Play card
  void playCard(dynamic card) {
    if (kDebugMode) print('🎮 Play card not implemented yet');
  }

  /// Reset game
  void resetGame() {
    _currentGame = null;
    _currentUser = null;
    _allPlayers.clear();
    _isMultiplayer = false;
    _isLoading = false;
    _errorMessage = null;
    if (kDebugMode) print('🎮 Game state reset');
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  /// Update game state from multiplayer service and trigger AI moves if needed
  void updateGameState(Map<String, dynamic> serverGameState) {
    if (!_isMultiplayer || !hasActiveGame) return;
    
    try {
      // Update game phase
      if (serverGameState.containsKey('phase')) {
        final phaseStr = serverGameState['phase'].toString().toLowerCase();
        switch (phaseStr) {
          case 'contractselection': _currentGame!.phase = GamePhase.contractSelection; break;
          case 'playing': _currentGame!.phase = GamePhase.playing; break;
          // Add other phases as needed
        }
      }
      
      // Update current contract
      if (serverGameState.containsKey('currentContract')) {
        final contractVal = serverGameState['currentContract'];
        if (contractVal != null && contractVal.toString().isNotEmpty && contractVal.toString() != 'null') {
          final contractStr = contractVal.toString().toLowerCase();
          switch (contractStr) {
            case 'kingofhearts':
            case 'king_of_hearts':
            case 'kingofheart':
            case 'king of hearts':
              _currentGame!.currentContract = TrexContract.kingOfHearts;
              break;
            case 'queens':
            case 'girls':
              _currentGame!.currentContract = TrexContract.queens;
              break;
            case 'diamonds':
            case 'dinari':
              _currentGame!.currentContract = TrexContract.diamonds;
              break;
            case 'collections':
            case 'hearts':
              _currentGame!.currentContract = TrexContract.collections;
              break;
            case 'trex':
            case 'trixnotricks':
              _currentGame!.currentContract = TrexContract.trex;
              break;
            default:
              // Try matching enum names directly
              try {
                _currentGame!.currentContract = TrexContract.values.firstWhere((e) => e.name.toLowerCase() == contractStr);
              } catch (_) {
                if (kDebugMode) print('⚠️ Unknown contract string from server: $contractVal');
              }
          }
        } else {
          _currentGame!.currentContract = null;
        }
      }
      
      // Update current king
      if (serverGameState.containsKey('currentKing')) {
        final currentKingStr = serverGameState['currentKing'].toString().toLowerCase();
        switch (currentKingStr) {
          case 'north': _currentGame!.currentKing = PlayerPosition.north; break;
          case 'south': _currentGame!.currentKing = PlayerPosition.south; break;
          case 'east': _currentGame!.currentKing = PlayerPosition.east; break;
          case 'west': _currentGame!.currentKing = PlayerPosition.west; break;
        }
      }
      
      // Update current player
      if (serverGameState.containsKey('currentPlayer')) {
        final currentPlayerStr = serverGameState['currentPlayer'].toString().toLowerCase();
        switch (currentPlayerStr) {
          case 'north': _currentGame!.currentPlayer = PlayerPosition.north; break;
          case 'south': _currentGame!.currentPlayer = PlayerPosition.south; break;
          case 'east': _currentGame!.currentPlayer = PlayerPosition.east; break;
          case 'west': _currentGame!.currentPlayer = PlayerPosition.west; break;
        }
      }
      
      if (kDebugMode) {
        print('🔄 Game state updated from server');
        print('   - Phase: ${_currentGame!.phase}');
        print('   - Current king: ${_currentGame!.currentKing}');
        print('   - Current player: ${_currentGame!.currentPlayer}');
        print('   - Is current player AI: $isCurrentPlayerAI');
      }
      
      // Schedule AI moves if needed
      _scheduleAIMovesIfNeeded();
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Failed to update game state: $e');
    }
  }

  /// Schedule AI moves if current player is AI
  void _scheduleAIMovesIfNeeded() {
    if (!_isMultiplayer || _multiplayerService == null || !hasActiveGame) return;
    
    // Cancel any existing timer
    _aiMoveTimer?.cancel();
    
    if (isCurrentPlayerAI) {
      if (kDebugMode) {
        print('🤖 Scheduling AI move for ${_currentGame!.phase == GamePhase.contractSelection ? 'contract selection' : 'card play'}');
      }
      
      // Schedule AI move after a short delay (1-3 seconds)
      _aiMoveTimer = Timer(Duration(milliseconds: 1500 + (DateTime.now().millisecond % 1500)), () {
        _makeAIMove();
      });
    }
  }
  
  /// Make an AI move based on current game phase
  void _makeAIMove() async {
    if (!_isMultiplayer || _multiplayerService == null || !hasActiveGame || !isCurrentPlayerAI) return;
    
    try {
      if (_currentGame!.phase == GamePhase.contractSelection) {
        await _makeAIContractSelection();
      } else if (_currentGame!.phase == GamePhase.playing) {
        await _makeAICardPlay();
      }
    } catch (e) {
      if (kDebugMode) print('❌ AI move failed: $e');
    }
  }
  
  /// Make AI contract selection
  Future<void> _makeAIContractSelection() async {
    if (_multiplayerService == null) return;
    
  // Simple AI contract selection - pick a random valid contract by enum name
  final contracts = ['kingOfHearts', 'queens', 'diamonds', 'collections', 'trex'];
    final selectedContract = contracts[DateTime.now().millisecond % contracts.length];
    
    if (kDebugMode) {
      print('🤖 AI selecting contract: $selectedContract');
    }
    
    // Call multiplayer service to send contract selection
    try {
      await _multiplayerService.selectContract(selectedContract);
    } catch (e) {
      if (kDebugMode) print('❌ AI contract selection failed: $e');
    }
  }
  
  /// Make AI card play (placeholder for future implementation)
  Future<void> _makeAICardPlay() async {
    if (kDebugMode) print('🤖 AI card play not implemented yet');
    // TODO: Implement AI card selection logic
  }

  @override
  void dispose() {
    _aiMoveTimer?.cancel();
    super.dispose();
  }
}