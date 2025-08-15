import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/multiplayer_models.dart';
import '../models/game.dart';
import '../models/card.dart';

/// Multiplayer service for real-time game communication
class MultiplayerService {
  static MultiplayerService? _instance;
  static MultiplayerService get instance => _instance ??= MultiplayerService._();
  
  MultiplayerService._();

  // Connection management
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _currentRoomId;
  String? _currentPlayerId;
  
  // Configuration
  static const String _serverUrl = 'ws://192.168.0.136:8080'; // Your server URL
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 5);
  
  // State management
  GameRoom? _currentRoom;
  MultiplayerGameState? _currentGameState;
  final List<GameRoom> _availableRooms = [];
  
  // Stream controllers for UI updates
  final StreamController<GameRoom> _roomUpdateController = StreamController<GameRoom>.broadcast();
  final StreamController<MultiplayerGameState> _gameStateController = StreamController<MultiplayerGameState>.broadcast();
  final StreamController<List<GameRoom>> _roomsListController = StreamController<List<GameRoom>>.broadcast();
  final StreamController<MultiplayerMessage> _messageController = StreamController<MultiplayerMessage>.broadcast();
  final StreamController<ConnectionStatus> _connectionController = StreamController<ConnectionStatus>.broadcast();
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentPlayerId => _currentPlayerId;
  GameRoom? get currentRoom => _currentRoom;
  MultiplayerGameState? get currentGameState => _currentGameState;
  List<GameRoom> get availableRooms => List.unmodifiable(_availableRooms);
  
  // Streams
  Stream<GameRoom> get roomUpdates => _roomUpdateController.stream;
  Stream<MultiplayerGameState> get gameStateUpdates => _gameStateController.stream;
  Stream<List<GameRoom>> get roomsListUpdates => _roomsListController.stream;
  Stream<MultiplayerMessage> get messages => _messageController.stream;
  Stream<ConnectionStatus> get connectionStatus => _connectionController.stream;

  /// Initialize the multiplayer service
  Future<void> initialize() async {
    if (kDebugMode) {
      print('🌐 Multiplayer Service initializing...');
    }
    
    await _loadPlayerId();
    await _checkConnectivity();
    
    if (kDebugMode) {
      print('✅ Multiplayer Service initialized');
    }
  }

  /// Connect to the multiplayer server
  Future<bool> connect() async {
    if (_isConnected || _isConnecting) return _isConnected;
    
    _isConnecting = true;
    _connectionController.add(ConnectionStatus.connecting);
    
    try {
      if (kDebugMode) {
        print('🔌 Connecting to multiplayer server: $_serverUrl');
      }
      
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      
      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleWebSocketError,
        onDone: _handleDisconnect,
      );
      
      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(ConnectionStatus.connected);
      
      // Start ping timer
      _startPingTimer();
      
      // Send authentication
      await _sendMessage(MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.ping.name,
        senderId: _currentPlayerId ?? 'anonymous',
        roomId: _currentRoomId ?? '',
        data: {'playerId': _currentPlayerId},
      ));
      
      if (kDebugMode) {
        print('✅ Connected to multiplayer server');
      }
      
      return true;
      
    } catch (e) {
      _isConnecting = false;
      _connectionController.add(ConnectionStatus.error);
      
      if (kDebugMode) {
        print('❌ Failed to connect to multiplayer server: $e');
      }
      
      // Schedule reconnect
      _scheduleReconnect();
      return false;
    }
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    if (kDebugMode) {
      print('🔌 Disconnecting from multiplayer server');
    }
    
    _stopPingTimer();
    _stopReconnectTimer();
    
    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }
    
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(ConnectionStatus.disconnected);
    
    if (kDebugMode) {
      print('✅ Disconnected from multiplayer server');
    }
  }

  /// Create a new game room
  Future<GameRoom?> createRoom({
    required String name,
    required GameRoomSettings settings,
  }) async {
    if (!_isConnected) {
      if (kDebugMode) print('❌ Not connected to server');
      return null;
    }
    
    try {
      final roomId = const Uuid().v4();
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.createRoom.name,
        senderId: _currentPlayerId!,
        roomId: roomId,
        data: {
          'name': name,
          'settings': settings.toJson(),
          'hostId': _currentPlayerId,
        },
      );
      
      await _sendMessage(message);
      
      // Wait for room creation response
      final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
      
      if (response != null && response.data['success'] == true) {
        final room = GameRoom.fromJson(response.data['room']);
        _currentRoom = room;
        _currentRoomId = room.id;
        
        if (kDebugMode) {
          print('✅ Created room: ${room.name}');
        }
        
        return room;
      }
      
      return null;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to create room: $e');
      }
      return null;
    }
  }

  /// Join an existing game room
  Future<bool> joinRoom(String roomId, {String? password}) async {
    if (!_isConnected) {
      if (kDebugMode) print('❌ Not connected to server');
      return false;
    }
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.joinRoom.name,
        senderId: _currentPlayerId!,
        roomId: roomId,
        data: {
          'password': password,
        },
      );
      
      await _sendMessage(message);
      
      // Wait for join response
      final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
      
      if (response != null && response.data['success'] == true) {
        final room = GameRoom.fromJson(response.data['room']);
        _currentRoom = room;
        _currentRoomId = room.id;
        
        if (kDebugMode) {
          print('✅ Joined room: ${room.name}');
        }
        
        return true;
      }
      
      return false;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to join room: $e');
      }
      return false;
    }
  }

  /// Leave the current room
  Future<void> leaveRoom() async {
    if (_currentRoomId == null) return;
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.leaveRoom.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {},
      );
      
      await _sendMessage(message);
      
      _currentRoom = null;
      _currentRoomId = null;
      _currentGameState = null;
      
      if (kDebugMode) {
        print('✅ Left room');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to leave room: $e');
      }
    }
  }

  /// Get list of available rooms
  Future<List<GameRoom>> getAvailableRooms() async {
    if (!_isConnected) {
      if (kDebugMode) print('❌ Not connected to server');
      return [];
    }
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: 'getRooms',
        senderId: _currentPlayerId!,
        roomId: '',
        data: {},
      );
      
      await _sendMessage(message);
      
      // Wait for rooms list response
      final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
      
      if (response != null && response.data['success'] == true) {
        final rooms = (response.data['rooms'] as List)
            .map((r) => GameRoom.fromJson(r))
            .toList();
        
        _availableRooms.clear();
        _availableRooms.addAll(rooms);
        _roomsListController.add(rooms);
        
        return rooms;
      }
      
      return [];
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to get rooms: $e');
      }
      return [];
    }
  }

  /// Start a game in the current room
  Future<bool> startGame() async {
    if (_currentRoom == null || !_currentRoom!.canStart) {
      if (kDebugMode) print('❌ Cannot start game: room not ready');
      return false;
    }
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.startGame.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {},
      );
      
      await _sendMessage(message);
      
      if (kDebugMode) {
        print('🎮 Starting game...');
      }
      
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to start game: $e');
      }
      return false;
    }
  }

  /// Play a card in the current game
  Future<bool> playCard(Card card) async {
    if (_currentGameState == null) {
      if (kDebugMode) print('❌ No active game');
      return false;
    }
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.cardPlayed.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {
          'card': card.toJson(),
          'gameId': _currentGameState!.gameId,
        },
      );
      
      await _sendMessage(message);
      
      if (kDebugMode) {
        print('🃏 Playing card: ${card.rank.englishName} of ${card.suit.englishName}');
      }
      
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to play card: $e');
      }
      return false;
    }
  }

  /// Select a contract
  Future<bool> selectContract(TrexContract contract) async {
    if (_currentGameState == null) {
      if (kDebugMode) print('❌ No active game');
      return false;
    }
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.contractSelected.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {
          'contract': contract.name,
          'gameId': _currentGameState!.gameId,
        },
      );
      
      await _sendMessage(message);
      
      if (kDebugMode) {
        print('📋 Selected contract: ${contract.englishName}');
      }
      
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to select contract: $e');
      }
      return false;
    }
  }

  /// Send a chat message
  Future<void> sendChatMessage(String message) async {
    if (_currentRoomId == null) return;
    
    try {
      final multiplayerMessage = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.chatMessage.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      await _sendMessage(multiplayerMessage);
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to send chat message: $e');
      }
    }
  }

  /// Set player ready status
  Future<void> setReady(bool isReady) async {
    if (_currentRoomId == null) return;
    
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.playerReady.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId!,
        data: {
          'isReady': isReady,
        },
      );
      
      await _sendMessage(message);
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to set ready status: $e');
      }
    }
  }

  // Private methods

  Future<void> _loadPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    _currentPlayerId = prefs.getString('player_id');
    
    if (_currentPlayerId == null) {
      _currentPlayerId = const Uuid().v4();
      await prefs.setString('player_id', _currentPlayerId!);
    }
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      _connectionController.add(ConnectionStatus.noInternet);
    }
  }

  Future<void> _sendMessage(MultiplayerMessage message) async {
    if (_channel == null) {
      throw Exception('Not connected to server');
    }
    
    final jsonMessage = jsonEncode(message.toJson());
    _channel!.sink.add(jsonMessage);
  }

  void _handleMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data.toString());
      final message = MultiplayerMessage.fromJson(jsonData);
      
      if (kDebugMode) {
        print('📨 Received message: ${message.type}');
      }
      
      _messageController.add(message);
      
      switch (message.type) {
        case 'roomUpdate':
          _handleRoomUpdate(message);
          break;
        case 'gameStateUpdate':
          _handleGameStateUpdate(message);
          break;
        case 'playerJoined':
          _handlePlayerJoined(message);
          break;
        case 'playerLeft':
          _handlePlayerLeft(message);
          break;
        case 'error':
          _handleError(message);
          break;
        case 'pong':
          _handlePong(message);
          break;
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling message: $e');
      }
    }
  }

  void _handleRoomUpdate(MultiplayerMessage message) {
    try {
      final room = GameRoom.fromJson(message.data['room']);
      _currentRoom = room;
      _roomUpdateController.add(room);
      
      if (kDebugMode) {
        print('🔄 Room updated: ${room.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling room update: $e');
      }
    }
  }

  void _handleGameStateUpdate(MultiplayerMessage message) {
    try {
      final gameState = MultiplayerGameState.fromJson(message.data['gameState']);
      _currentGameState = gameState;
      _gameStateController.add(gameState);
      
      if (kDebugMode) {
        print('🎮 Game state updated: ${gameState.phase.englishName}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling game state update: $e');
      }
    }
  }

  void _handlePlayerJoined(MultiplayerMessage message) {
    if (kDebugMode) {
      print('👋 Player joined: ${message.data['playerName']}');
    }
  }

  void _handlePlayerLeft(MultiplayerMessage message) {
    if (kDebugMode) {
      print('👋 Player left: ${message.data['playerName']}');
    }
  }

  void _handleError(MultiplayerMessage message) {
    if (kDebugMode) {
      print('❌ Server error: ${message.data['error']}');
    }
  }

  void _handlePong(MultiplayerMessage message) {
    if (kDebugMode) {
      print('🏓 Pong received');
    }
  }

  void _handleWebSocketError(dynamic error) {
    if (kDebugMode) {
      print('❌ WebSocket error: $error');
    }
    _connectionController.add(ConnectionStatus.error);
  }

  void _handleDisconnect() {
    if (kDebugMode) {
      print('🔌 WebSocket disconnected');
    }
    
    _isConnected = false;
    _connectionController.add(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (_isConnected) {
        _sendPing();
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _sendPing() async {
    try {
      final message = MultiplayerMessage(
        id: const Uuid().v4(),
        type: MessageType.ping.name,
        senderId: _currentPlayerId!,
        roomId: _currentRoomId ?? '',
        data: {},
      );
      
      await _sendMessage(message);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to send ping: $e');
      }
    }
  }

  void _scheduleReconnect() {
    _stopReconnectTimer();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && !_isConnecting) {
        connect();
      }
    });
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<MultiplayerMessage?> _waitForResponse(String messageId, {Duration? timeout}) async {
    final completer = Completer<MultiplayerMessage?>();
    final timer = timeout != null ? Timer(timeout, () => completer.complete(null)) : null;
    
    late StreamSubscription<MultiplayerMessage> subscription;
    subscription = _messageController.stream.listen((message) {
      if (message.data['responseTo'] == messageId) {
        subscription.cancel();
        timer?.cancel();
        completer.complete(message);
      }
    });
    
    return completer.future;
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _roomUpdateController.close();
    _gameStateController.close();
    _roomsListController.close();
    _messageController.close();
    _connectionController.close();
  }
}

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  noInternet,
}
