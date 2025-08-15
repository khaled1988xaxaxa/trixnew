import 'package:flutter/foundation.dart';
import '../services/multiplayer_service.dart';
import '../models/multiplayer_models.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/card.dart';

/// Provider for managing multiplayer game state
class MultiplayerProvider with ChangeNotifier {
  final MultiplayerService _multiplayerService = MultiplayerService.instance;
  
  // State
  bool _isInitialized = false;
  bool _isConnecting = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  GameRoom? _currentRoom;
  MultiplayerGameState? _currentGameState;
  List<GameRoom> _availableRooms = [];
  List<MultiplayerMessage> _chatMessages = [];
  String? _errorMessage;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isConnecting => _isConnecting;
  ConnectionStatus get connectionStatus => _connectionStatus;
  GameRoom? get currentRoom => _currentRoom;
  MultiplayerGameState? get currentGameState => _currentGameState;
  List<GameRoom> get availableRooms => _availableRooms;
  List<MultiplayerMessage> get chatMessages => _chatMessages;
  String? get errorMessage => _errorMessage;
  
  bool get isConnected => _multiplayerService.isConnected;
  bool get isInRoom => _currentRoom != null;
  bool get canStartGame => _currentRoom?.canStart ?? false;
  bool get isGameActive => _currentGameState != null;

  /// Initialize the multiplayer provider
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _multiplayerService.initialize();
      
      // Listen to connection status
      _multiplayerService.connectionStatus.listen((status) {
        _connectionStatus = status;
        _isConnecting = status == ConnectionStatus.connecting;
        notifyListeners();
      });
      
      // Listen to room updates
      _multiplayerService.roomUpdates.listen((room) {
        _currentRoom = room;
        notifyListeners();
      });
      
      // Listen to game state updates
      _multiplayerService.gameStateUpdates.listen((gameState) {
        _currentGameState = gameState;
        _syncWithGameProvider(gameState);
        notifyListeners();
      });
      
      // Listen to rooms list updates
      _multiplayerService.roomsListUpdates.listen((rooms) {
        _availableRooms = rooms;
        notifyListeners();
      });
      
      // Listen to messages (for chat)
      _multiplayerService.messages.listen((message) {
        if (message.type == MessageType.chatMessage.name) {
          _chatMessages.add(message);
          notifyListeners();
        }
      });
      
      _isInitialized = true;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ Multiplayer Provider initialized');
      }
      
    } catch (e) {
      _errorMessage = 'Failed to initialize multiplayer: $e';
      notifyListeners();
      
      if (kDebugMode) {
        print('❌ Failed to initialize multiplayer provider: $e');
      }
    }
  }

  /// Connect to multiplayer server
  Future<bool> connect() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      _isConnecting = true;
      notifyListeners();
      
      final success = await _multiplayerService.connect();
      
      if (success) {
        // Get available rooms after connection
        await getAvailableRooms();
      }
      
      return success;
      
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      notifyListeners();
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    await _multiplayerService.disconnect();
    _currentRoom = null;
    _currentGameState = null;
    _availableRooms.clear();
    _chatMessages.clear();
    notifyListeners();
  }

  /// Create a new game room
  Future<GameRoom?> createRoom({
    required String name,
    GameRoomSettings? settings,
  }) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      final room = await _multiplayerService.createRoom(
        name: name,
        settings: settings ?? const GameRoomSettings(),
      );
      
      if (room != null) {
        _currentRoom = room;
        notifyListeners();
      }
      
      return room;
      
    } catch (e) {
      _errorMessage = 'Failed to create room: $e';
      notifyListeners();
      return null;
    }
  }

  /// Join an existing room
  Future<bool> joinRoom(String roomId, {String? password}) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      final success = await _multiplayerService.joinRoom(roomId, password: password);
      
      if (success) {
        // Room will be updated via stream
        if (kDebugMode) {
          print('✅ Joined room: $roomId');
        }
      }
      
      return success;
      
    } catch (e) {
      _errorMessage = 'Failed to join room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Leave current room
  Future<void> leaveRoom() async {
    try {
      await _multiplayerService.leaveRoom();
      _currentRoom = null;
      _currentGameState = null;
      _chatMessages.clear();
      notifyListeners();
      
    } catch (e) {
      _errorMessage = 'Failed to leave room: $e';
      notifyListeners();
    }
  }

  /// Get available rooms
  Future<List<GameRoom>> getAvailableRooms() async {
    try {
      final rooms = await _multiplayerService.getAvailableRooms();
      _availableRooms = rooms;
      notifyListeners();
      return rooms;
      
    } catch (e) {
      _errorMessage = 'Failed to get rooms: $e';
      notifyListeners();
      return [];
    }
  }

  /// Start a game in current room
  Future<bool> startGame() async {
    if (!canStartGame) {
      _errorMessage = 'Cannot start game: room not ready';
      notifyListeners();
      return false;
    }
    
    try {
      _errorMessage = null;
      notifyListeners();
      
      final success = await _multiplayerService.startGame();
      
      if (success) {
        if (kDebugMode) {
          print('🎮 Game started in room: ${_currentRoom?.name}');
        }
      }
      
      return success;
      
    } catch (e) {
      _errorMessage = 'Failed to start game: $e';
      notifyListeners();
      return false;
    }
  }

  /// Play a card in current game
  Future<bool> playCard(Card card) async {
    if (!isGameActive) {
      _errorMessage = 'No active game';
      notifyListeners();
      return false;
    }
    
    try {
      final success = await _multiplayerService.playCard(card);
      
      if (success) {
        if (kDebugMode) {
          print('🃏 Card played: ${card.rank.englishName} of ${card.suit.englishName}');
        }
      }
      
      return success;
      
    } catch (e) {
      _errorMessage = 'Failed to play card: $e';
      notifyListeners();
      return false;
    }
  }

  /// Select a contract
  Future<bool> selectContract(TrexContract contract) async {
    if (!isGameActive) {
      _errorMessage = 'No active game';
      notifyListeners();
      return false;
    }
    
    try {
      final success = await _multiplayerService.selectContract(contract);
      
      if (success) {
        if (kDebugMode) {
          print('📋 Contract selected: ${contract.englishName}');
        }
      }
      
      return success;
      
    } catch (e) {
      _errorMessage = 'Failed to select contract: $e';
      notifyListeners();
      return false;
    }
  }

  /// Send a chat message
  Future<void> sendChatMessage(String message) async {
    if (!isInRoom) return;
    
    try {
      await _multiplayerService.sendChatMessage(message);
      
    } catch (e) {
      _errorMessage = 'Failed to send message: $e';
      notifyListeners();
    }
  }

  /// Set player ready status
  Future<void> setReady(bool isReady) async {
    if (!isInRoom) return;
    
    try {
      await _multiplayerService.setReady(isReady);
      
    } catch (e) {
      _errorMessage = 'Failed to set ready status: $e';
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get current player session
  PlayerSession? getCurrentPlayerSession() {
    if (_currentRoom == null) return null;
    
    return _currentRoom!.getPlayerById(_multiplayerService.currentPlayerId ?? '');
  }

  /// Check if current player is host
  bool get isHost {
    final session = getCurrentPlayerSession();
    return session?.isHost ?? false;
  }

  /// Check if current player is ready
  bool get isReady {
    final session = getCurrentPlayerSession();
    return session?.isReady ?? false;
  }

  /// Get player's hand from multiplayer state
  List<Card> getPlayerHand() {
    if (_currentGameState == null) return [];
    
    final session = getCurrentPlayerSession();
    if (session == null) return [];
    
    return _currentGameState!.playerHands[session.position] ?? [];
  }

  /// Get other players' hand counts
  Map<PlayerPosition, int> getOtherPlayersHandCounts() {
    if (_currentGameState == null) return {};
    
    final session = getCurrentPlayerSession();
    if (session == null) return {};
    
    final result = <PlayerPosition, int>{};
    for (final entry in _currentGameState!.playerHands.entries) {
      if (entry.key != session.position) {
        result[entry.key] = entry.value.length;
      }
    }
    
    return result;
  }

  /// Sync multiplayer game state with game provider
  void _syncWithGameProvider(MultiplayerGameState gameState) {
    // This method will be called when game state updates
    // It should sync the multiplayer state with the local game provider
    // Implementation depends on how you want to handle the integration
    
    if (kDebugMode) {
      print('🔄 Syncing multiplayer state with game provider');
      print('   Phase: ${gameState.phase.englishName}');
      print('   Current Player: ${gameState.currentPlayer.englishName}');
      print('   Scores: ${gameState.scores}');
    }
  }

  /// Convert multiplayer game state to local game
  TrexGame? convertToLocalGame(MultiplayerGameState gameState) {
    try {
      // Create players from multiplayer state
      final players = <Player>[];
      
      for (final entry in gameState.playerHands.entries) {
        final position = entry.key;
        final hand = entry.value;
        
        // Find player session for this position
        final session = _currentRoom?.players.firstWhere(
          (p) => p.position == position,
          orElse: () => PlayerSession(
            id: 'unknown',
            name: position.englishName,
            position: position,
          ),
        );
        
        final player = Player(
          id: session?.id ?? 'unknown',
          name: session?.name ?? position.englishName,
          position: position,
          hand: hand,
          isBot: false, // All players in multiplayer are human
        );
        
        players.add(player);
      }
      
      // Create game
      final game = TrexGame(
        players: players,
        firstKing: gameState.currentKing,
      );
      
      // Set game state
      game.phase = gameState.phase;
      game.currentContract = gameState.currentContract;
      game.currentPlayer = gameState.currentPlayer;
      game.currentKing = gameState.currentKing;
      game.round = gameState.round;
      game.kingdom = gameState.kingdom;
      
      // Set scores
      for (final entry in gameState.scores.entries) {
        final player = players.firstWhere((p) => p.position == entry.key);
        player.score = entry.value;
      }
      
      // Set current trick
      if (gameState.currentTrick != null) {
        game.currentTrick = gameState.currentTrick;
      }
      
      // Set completed tricks
      game.tricks.clear();
      game.tricks.addAll(gameState.completedTricks);
      
      return game;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to convert multiplayer state to local game: $e');
      }
      return null;
    }
  }

  /// Get room statistics
  Map<String, dynamic> getRoomStats() {
    if (_currentRoom == null) return {};
    
    return {
      'name': _currentRoom!.name,
      'playerCount': _currentRoom!.players.length,
      'maxPlayers': _currentRoom!.settings.maxPlayers,
      'status': _currentRoom!.status.name,
      'isFull': _currentRoom!.isFull,
      'canStart': _currentRoom!.canStart,
      'readyPlayers': _currentRoom!.players.where((p) => p.isReady).length,
      'hostName': _currentRoom!.getHost()?.name ?? 'Unknown',
    };
  }

  /// Get game statistics
  Map<String, dynamic> getGameStats() {
    if (_currentGameState == null) return {};
    
    return {
      'phase': _currentGameState!.phase.englishName,
      'contract': _currentGameState!.currentContract?.englishName ?? 'None',
      'currentPlayer': _currentGameState!.currentPlayer.englishName,
      'round': _currentGameState!.round,
      'kingdom': _currentGameState!.kingdom,
      'scores': _currentGameState!.scores,
      'completedTricks': _currentGameState!.completedTricks.length,
    };
  }

  @override
  void dispose() {
    _multiplayerService.dispose();
    super.dispose();
  }
}
