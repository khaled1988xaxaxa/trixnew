import 'package:flutter/foundation.dart';
import '../services/multiplayer_service.dart';
import '../models/multiplayer_models.dart';

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
  bool get isConnected => _connectionStatus == ConnectionStatus.connected;
  ConnectionStatus get connectionStatus => _connectionStatus;
  GameRoom? get currentRoom => _currentRoom;
  MultiplayerGameState? get currentGameState => _currentGameState;
  List<GameRoom> get availableRooms => _availableRooms;
  List<MultiplayerMessage> get chatMessages => _chatMessages;
  String? get errorMessage => _errorMessage;

  bool get isInRoom => _currentRoom != null;
  bool get isGameActive => _currentGameState != null;

  /// Connect to multiplayer service (compatibility method)
  Future<void> connect() async {
    await initialize();
  }

  /// Initialize the multiplayer provider
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _isConnecting = true;
      _connectionStatus = ConnectionStatus.connecting;
      notifyListeners();
      
      // Connect to the multiplayer service
      final connected = await _multiplayerService.connect();
      
      if (connected) {
        _connectionStatus = ConnectionStatus.connected;
        
        // Listen to room updates
        _multiplayerService.roomUpdateStream.listen((room) {
          _currentRoom = room;
          notifyListeners();
        });
        
        // Listen to game state updates
        _multiplayerService.gameStateStream.listen((gameState) {
          _currentGameState = gameState;
          notifyListeners();
        });
        
        // Listen to messages
        _multiplayerService.messageStream.listen((message) {
          if (message.type == 'chatMessage') {
            _chatMessages.add(message);
            notifyListeners();
          }
        });
        
        _isInitialized = true;
      } else {
        _connectionStatus = ConnectionStatus.error;
        _errorMessage = 'Failed to connect to server';
      }
      
      _isConnecting = false;
      notifyListeners();
      
    } catch (e) {
      _connectionStatus = ConnectionStatus.error;
      _errorMessage = 'Connection failed: $e';
      notifyListeners();
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    _multiplayerService.disconnect();
    _currentRoom = null;
    _currentGameState = null;
    _availableRooms.clear();
    _chatMessages.clear();
    _connectionStatus = ConnectionStatus.disconnected;
    _isInitialized = false;
    notifyListeners();
  }

  /// Create a new room
  Future<GameRoom?> createRoom({
    required String name,
    GameRoomSettings? settings,
  }) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      final room = await _multiplayerService.createRoom(name);
      
      if (room != null) {
        _currentRoom = room;
        notifyListeners();
        return room;
      }
      
      return null;
      
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
      
      final room = await _multiplayerService.joinRoom(roomId);
      
      if (room != null) {
        _currentRoom = room;
        notifyListeners();
        if (kDebugMode) {
          print('✅ Joined room: $roomId');
        }
        return true;
      }
      
      return false;
      
    } catch (e) {
      _errorMessage = 'Failed to join room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Leave current room
  Future<bool> leaveRoom() async {
    if (_currentRoom == null) return false;
    
    try {
      final success = await _multiplayerService.leaveRoom();
      if (success) {
        _currentRoom = null;
        _currentGameState = null;
        notifyListeners();
      }
      return success;
    } catch (e) {
      _errorMessage = 'Failed to leave room: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get available rooms (compatibility method)
  Future<void> getAvailableRooms() async {
    await refreshAvailableRooms();
  }

  /// Get available rooms
  Future<void> refreshAvailableRooms() async {
    try {
      final rooms = await _multiplayerService.getAvailableRooms();
      _availableRooms = rooms;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load rooms: $e';
      notifyListeners();
    }
  }

  /// Set player ready status
  Future<void> setReady(bool isReady) async {
    try {
      await _multiplayerService.setReady(isReady);
    } catch (e) {
      _errorMessage = 'Failed to set ready status: $e';
      notifyListeners();
    }
  }

  /// Start game (compatibility method - games auto-start when ready)
  Future<void> startGame() async {
    // In our implementation, games start automatically when all players are ready
    if (kDebugMode) {
      print('🎮 Game will start automatically when all players are ready');
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Get current player session
  PlayerSession? getCurrentPlayerSession() {
    if (_currentRoom == null || _multiplayerService.playerId == null) {
      return null;
    }
    return _currentRoom!.getPlayerById(_multiplayerService.playerId!);
  }

  /// Check if current player is host
  bool get isHost {
    final session = getCurrentPlayerSession();
    return session?.id == _currentRoom?.hostId;
  }

  /// Check if current player is ready
  bool get isReady {
    final session = getCurrentPlayerSession();
    return session?.isReady ?? false;
  }

  @override
  void dispose() {
    _multiplayerService.dispose();
    super.dispose();
  }
}
