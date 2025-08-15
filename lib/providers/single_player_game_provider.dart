import 'package:flutter/foundation.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../services/game_logger.dart';

/// Dedicated provider for single-player games
/// This handles only local game logic with AI opponents
class SinglePlayerGameProvider with ChangeNotifier {
  TrexGame? _game;
  bool _isLoading = false;
  String? _errorMessage;
  final GameLogger _logger = GameLogger();
  PlayerPosition? _humanPlayerPosition;
  
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

  /// Initialize single-player game with AI opponents
  Future<void> initializeGame(Player humanPlayer, List<Player> aiPlayers) async {
    if (kDebugMode) {
      print('🎮 ===== INITIALIZE SINGLE-PLAYER GAME =====');
      print('🎮 Human player: "${humanPlayer.name}" (${humanPlayer.position.name})');
      print('🎮 AI players count: ${aiPlayers.length}');
      print('🎮 ==========================================');
    }
    
    _isLoading = true;
    _errorMessage = null;
    _humanPlayerPosition = humanPlayer.position;
    notifyListeners();

    try {
      // Initialize logging system
      await _logger.initialize();
      
      // Create all players (human + AI)
      final allPlayers = <Player>[humanPlayer, ...aiPlayers];
      
      // Create new single-player game with human player as first king
      _game = TrexGame(players: allPlayers, firstKing: _humanPlayerPosition!);
      
      if (kDebugMode) {
        print('✅ Single-player game initialized successfully');
        print('🎯 Game phase: ${_game!.phase}');
        print('🎯 Current player: ${_game!.currentPlayer.name}');
        print('🎯 Players: ${_game!.players.map((p) => '${p.name}(${p.position.name})').join(', ')}');
      }
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e, s) {
      _isLoading = false;
      _game = null;
      _errorMessage = 'Error initializing single-player game: ${e.toString()}';
      if (kDebugMode) {
        print('❌ ===== ERROR IN initializeSinglePlayerGame =====');
        print('❌ Error: $e');
        print('❌ Stack Trace: $s');
        print('❌ ===============================================');
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Select contract (local only)
  void selectContract(TrexContract contract) {
    if (_game == null || _game!.phase != GamePhase.contractSelection) return;
    
    try {
      if (kDebugMode) {
        print('🎮 Selecting contract locally: ${contract.name}');
      }
      
      // Log the contract selection
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logContractSelection(contract, _game!.availableContracts, humanPlayer);
      }
      
      // Update local game state
      _game!.selectContract(contract);
      
      if (kDebugMode) {
        print('✅ Contract selected: ${_game!.currentContract}');
        print('🎯 Game phase now: ${_game!.phase}');
      }
      
      notifyListeners();
      
    } catch (e) {
      _errorMessage = 'Error selecting contract: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Play card (local only)
  void playCard(Card card) {
    if (_game == null || _game!.phase != GamePhase.playing) return;
    
    if (!isHumanPlayerTurn) {
      if (kDebugMode) print('⚠️ Not human player\'s turn to play card');
      return;
    }
    
    try {
      if (kDebugMode) {
        print('🎮 Playing card locally: ${card.suit.name} ${card.rank.name}');
      }
      
      // Log the card play
      final humanPlayer = currentUser;
      if (humanPlayer != null) {
        _logger.logCardPlay(card, humanPlayer, _game!);
      }
      
      // Update local game state
      _game!.playCard(_humanPlayerPosition!, card);
      
      if (kDebugMode) {
        print('✅ Card played: ${card.suit.name} ${card.rank.name}');
        print('🎯 Current player now: ${_game!.currentPlayer.name}');
      }
      
      notifyListeners();
      
    } catch (e) {
      _errorMessage = 'Error playing card: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Reset game state
  void resetGame() {
    _game = null;
    _isLoading = false;
    _errorMessage = null;
    _humanPlayerPosition = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
