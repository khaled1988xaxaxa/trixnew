import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/multiplayer_models.dart';

class MultiplayerService {
  static MultiplayerService? _instance;
  static MultiplayerService get instance => _instance ??= MultiplayerService._();
  
  MultiplayerService._();

  // Connection management
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  bool _isConnected = false;
  String? _playerId;
  String? _playerName;
  String? _currentRoomId;
  GameRoom? _currentRoom;
  MultiplayerGameState? _currentGameState;
  
  // Stream controllers for real-time updates
  final StreamController<MultiplayerMessage> _messageController = StreamController<MultiplayerMessage>.broadcast();
  final StreamController<GameRoom> _roomUpdateController = StreamController<GameRoom>.broadcast();
  final StreamController<MultiplayerGameState> _gameStateController = StreamController<MultiplayerGameState>.broadcast();
  final StreamController<Map<String, dynamic>> _completers = StreamController<Map<String, dynamic>>();
  
  // Response tracking for request-response pattern
  final Map<String, Completer<MultiplayerMessage>> _pendingRequests = {};
  
  // Public streams
  Stream<MultiplayerMessage> get messageStream => _messageController.stream;
  Stream<GameRoom> get roomUpdateStream => _roomUpdateController.stream;
  Stream<MultiplayerGameState> get gameStateStream => _gameStateController.stream;
  
  // Getters
  bool get isConnected => _isConnected;
  String? get playerId => _playerId;
  String? get playerName => _playerName;
  String? get currentRoomId => _currentRoomId;
  GameRoom? get currentRoom => _currentRoom;
  MultiplayerGameState? get currentGameState => _currentGameState;

  Future<bool> connect({String? playerName}) async {
    if (_isConnected) {
      if (kDebugMode) {
        print('🔗 Already connected to multiplayer server');
      }
      return true;
    }

    try {
      // Get server URL based on platform
      final serverUrl = await _getServerUrl();
      
      if (kDebugMode) {
        print('🔗 Connecting to: $serverUrl');
      }

      _channel = WebSocketChannel.connect(
        Uri.parse(serverUrl),
      );

      // Set up message handling
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          if (kDebugMode) {
            print('❌ WebSocket error: $error');
          }
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) {
            print('🔌 WebSocket connection closed');
          }
          _handleDisconnect();
        },
      );

      // Generate player ID and store player name
      _playerId = const Uuid().v4();
      _playerName = playerName ?? 'Player ${_playerId!.substring(0, 8)}';
      
      // Save player info
      await _savePlayerInfo();

      _isConnected = true;
      
      // Start ping timer
      _startPingTimer();

      if (kDebugMode) {
        print('✅ Connected to multiplayer server as $_playerName');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to connect to multiplayer server: $e');
      }
      return false;
    }
  }

  Future<String> _getServerUrl() async {
    // Check if we're on web or mobile
    final connectivityResult = await Connectivity().checkConnectivity();
    
    if (kIsWeb) {
      // For web, use localhost
      return 'ws://localhost:8081';
    } else {
      // For mobile, use the computer's IP address
      return 'ws://192.168.0.80:8081';
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _sendPing();
      }
    });
  }

  void _sendPing() {
    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'ping',
      senderId: _playerId!,
      roomId: _currentRoomId ?? '',
      data: {'timestamp': DateTime.now().toIso8601String()},
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
  }

  Future<void> _savePlayerInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('multiplayer_player_id', _playerId!);
    await prefs.setString('multiplayer_player_name', _playerName!);
  }

  Future<void> _loadPlayerInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _playerId = prefs.getString('multiplayer_player_id');
    _playerName = prefs.getString('multiplayer_player_name');
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close(status.normalClosure);
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _playerId = null;
    _playerName = null;
    _currentRoomId = null;
    _currentRoom = null;
    _currentGameState = null;
    _pingTimer?.cancel();
    
    // Complete any pending requests with timeout
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError('Connection lost');
      }
    }
    _pendingRequests.clear();
  }

  void _sendMessage(MultiplayerMessage message) {
    if (_channel != null && _isConnected) {
      final jsonString = jsonEncode(message.toJson());
      _channel!.sink.add(jsonString);
      
      if (kDebugMode) {
        print('📤 Sent: ${message.type}');
      }
    }
  }

  Future<MultiplayerMessage?> _waitForResponse(String messageId, {Duration timeout = const Duration(seconds: 5)}) async {
    final completer = Completer<MultiplayerMessage>();
    _pendingRequests[messageId] = completer;
    
    try {
      return await completer.future.timeout(timeout);
    } catch (e) {
      _pendingRequests.remove(messageId);
      if (kDebugMode) {
        print('⏰ Request timeout for message: $messageId');
      }
      return null;
    }
  }

  Future<GameRoom?> createRoom(String roomName, {int maxPlayers = 4}) async {
    if (!_isConnected || _playerId == null) {
      throw Exception('Not connected to server');
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'createRoom',
      senderId: _playerId!,
      roomId: '',
      data: {
        'roomName': roomName,
        'maxPlayers': maxPlayers,
        'playerName': _playerName,
      },
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    if (kDebugMode) {
      print('🏠 Creating room: $roomName');
    }

    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
    
    if (response != null && response.data['success'] == true) {
      final room = GameRoom.fromJson(response.data['room']);
      _currentRoom = room;
      _currentRoomId = room.id;
      
      if (kDebugMode) {
        print('✅ Created room: ${room.name}');
      }
      
      return room;
    } else {
      if (kDebugMode) {
        print('❌ Failed to create room: ${response?.data['error'] ?? 'Unknown error'}');
      }
      return null;
    }
  }

  Future<GameRoom?> joinRoom(String roomId) async {
    if (!_isConnected || _playerId == null) {
      throw Exception('Not connected to server');
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'joinRoom',
      senderId: _playerId!,
      roomId: roomId,
      data: {
        'roomId': roomId,
        'playerName': _playerName,
      },
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    if (kDebugMode) {
      print('🏃 Joining room: $roomId');
    }

    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
    
    if (response != null && response.data['success'] == true) {
      final room = GameRoom.fromJson(response.data['room']);
      _currentRoom = room;
      _currentRoomId = room.id;
      
      if (kDebugMode) {
        print('✅ Joined room: ${room.name}');
      }
      
      return room;
    } else {
      if (kDebugMode) {
        print('❌ Failed to join room: ${response?.data['error'] ?? 'Unknown error'}');
      }
      return null;
    }
  }

  Future<bool> leaveRoom() async {
    if (!_isConnected || _playerId == null || _currentRoomId == null) {
      return false;
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'leaveRoom',
      senderId: _playerId!,
      roomId: _currentRoomId!,
      data: {},
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    if (kDebugMode) {
      print('🚪 Leaving room: $_currentRoomId');
    }

    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 5));
    
    if (response != null && response.data['success'] == true) {
      _currentRoom = null;
      _currentRoomId = null;
      _currentGameState = null;
      
      if (kDebugMode) {
        print('✅ Left room');
      }
      
      return true;
    }
    
    return false;
  }

  Future<bool> setReady(bool isReady) async {
    if (!_isConnected || _playerId == null || _currentRoomId == null) {
      if (kDebugMode) {
        print('❌ Cannot set ready: not connected or not in room');
        print('   Connected: $_isConnected, PlayerId: $_playerId, RoomId: $_currentRoomId');
      }
      return false;
    }

    if (kDebugMode) {
      print('🔄 Setting ready status to $isReady in room $_currentRoomId');
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'playerReady',
      senderId: _playerId!,
      roomId: _currentRoomId!,
      data: {
        'roomId': _currentRoomId,
        'isReady': isReady,
      },
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    if (kDebugMode) {
      print('📤 Sent ready message with roomId: $_currentRoomId');
    }

    // For ready status, we don't wait for response as it's handled via room updates
    return true;
  }

  Future<List<GameRoom>> getAvailableRooms() async {
    if (!_isConnected || _playerId == null) {
      return [];
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'getRooms',
      senderId: _playerId!,
      roomId: '',
      data: {},
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
    
    if (response != null && response.data['rooms'] != null) {
      final roomsData = response.data['rooms'] as List;
      return roomsData.map((roomJson) => GameRoom.fromJson(roomJson)).toList();
    }
    
    return [];
  }

  void _handleMessage(dynamic data) {
    try {
      final jsonData = jsonDecode(data.toString());
      final message = MultiplayerMessage.fromJson(jsonData);
      
      if (kDebugMode) {
        print('📨 Received message: ${message.type}');
      }
      
      _messageController.add(message);
      
      // Check if this is a response to a pending request
      if (_pendingRequests.containsKey(message.id)) {
        final completer = _pendingRequests.remove(message.id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      }
      
      switch (message.type) {
        case 'roomUpdate':
          _handleRoomUpdate(message);
          break;
        case 'gameStarted':
          _handleGameStarted(message);
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

  void _handleGameStarted(MultiplayerMessage message) {
    try {
      if (kDebugMode) {
        print('🎮 Game started! ${message.data['message']}');
      }
      
      // Navigate to game screen
      // You'll need to implement navigation logic here
      // For now, just update the room state
      if (message.data['gameState'] != null) {
        // Handle game state if provided
        if (kDebugMode) {
          print('🎯 Game state received');
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling game started: $e');
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

  void dispose() {
    disconnect();
    _messageController.close();
    _roomUpdateController.close();
    _gameStateController.close();
    _completers.close();
  }
}
