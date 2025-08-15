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
  final StreamController<Map<String, dynamic>> _gameStartedController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _completers = StreamController<Map<String, dynamic>>();
  
  // Response tracking for request-response pattern
  final Map<String, Completer<MultiplayerMessage>> _pendingRequests = {};
  
  // Public streams
  Stream<MultiplayerMessage> get messageStream => _messageController.stream;
  Stream<GameRoom> get roomUpdateStream => _roomUpdateController.stream;
  Stream<MultiplayerGameState> get gameStateStream => _gameStateController.stream;
  Stream<Map<String, dynamic>> get gameStartedStream => _gameStartedController.stream;
  
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
    // Try to detect the correct host for web builds. Using 'localhost' on web
    // makes the browser try to connect to the device itself (phone), which
    // breaks multi-device play. Use the page's host if available so remote
    // devices connect back to the server machine.
  await Connectivity().checkConnectivity();

  if (kIsWeb) {
  // Use the host where the web page is served from, but always target
  // the multiplayer server port (8080) instead of the flutter dev port.
  // This prevents the browser from trying to connect to the dev server
  // websocket port (e.g. 59213) which the multiplayer server doesn't listen on.
  final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
  final port = 8080;
  return 'ws://$host:$port';
    } else {
      // For mobile/desktop, use the configured local IP (fallback). You can
      // update this IP to your machine's LAN IP if needed.
      return 'ws://192.168.0.80:8080';
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

  Future<bool> kickPlayer(String targetPlayerId) async {
    if (!_isConnected || _playerId == null || _currentRoomId == null) {
      if (kDebugMode) {
        print('❌ Cannot kick player: not connected or not in room');
      }
      return false;
    }

    // Check if current player is host
    if (_currentRoom?.hostId != _playerId) {
      if (kDebugMode) {
        print('❌ Cannot kick player: not the room host');
      }
      return false;
    }

    if (kDebugMode) {
      print('👢 Kicking player $targetPlayerId from room $_currentRoomId');
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'kickPlayer',
      senderId: _playerId!,
      roomId: _currentRoomId!,
      data: {
        'roomId': _currentRoomId,
        'targetPlayerId': targetPlayerId,
      },
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 5));
    
    if (response != null && response.data['success'] == true) {
      if (kDebugMode) {
        final kickedPlayer = response.data['kickedPlayer'];
        print('✅ Successfully kicked ${kickedPlayer['name']} (${kickedPlayer['isAI'] ? 'AI' : 'Human'})');
      }
      return true;
    } else {
      if (kDebugMode) {
        print('❌ Failed to kick player: ${response?.data['error'] ?? 'Unknown error'}');
      }
      return false;
    }
  }

  Future<bool> startGame() async {
    if (!_isConnected || _playerId == null || _currentRoomId == null) {
      if (kDebugMode) {
        print('❌ Cannot start game: not connected or not in room');
      }
      return false;
    }

    // Check if current player is host
    if (_currentRoom?.hostId != _playerId) {
      if (kDebugMode) {
        print('❌ Cannot start game: not the room host');
      }
      return false;
    }

    if (kDebugMode) {
      print('🎮 Starting game in room $_currentRoomId');
    }

    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'startGame',
      senderId: _playerId!,
      roomId: _currentRoomId!,
      data: {
        'roomId': _currentRoomId,
      },
      timestamp: DateTime.now(),
    );

    _sendMessage(message);
    
    final response = await _waitForResponse(message.id, timeout: const Duration(seconds: 10));
    
    if (response != null && response.data['success'] == true) {
      if (kDebugMode) {
        print('✅ Successfully started game');
      }
      return true;
    } else {
      if (kDebugMode) {
        print('❌ Failed to start game: ${response?.data['error'] ?? 'Unknown error'}');
      }
      return false;
    }
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
      if (message.type == 'response' && message.data.containsKey('responseTo')) {
        final responseTo = message.data['responseTo'];
        if (kDebugMode) {
          print('🔍 Response received for message ID: $responseTo');
          print('🔍 Pending requests: ${_pendingRequests.keys.toList()}');
        }
        if (_pendingRequests.containsKey(responseTo)) {
          final completer = _pendingRequests.remove(responseTo);
          if (completer != null && !completer.isCompleted) {
            if (kDebugMode) {
              print('✅ Completing request: $responseTo');
            }
            completer.complete(message);
          }
        } else {
          if (kDebugMode) {
            print('❌ No pending request found for: $responseTo');
          }
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
        case 'kicked':
          _handleKicked(message);
          break;
        case 'playerKicked':
          _handlePlayerKicked(message);
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
      if (kDebugMode) {
        print('🔍 Raw room data: ${message.data}');
        print('🔍 Room object: ${message.data['room']}');
      }
      
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
        print('🎯 Game started message data: ${message.data.keys}');
      }
      
      // Use room data from message if available, otherwise use current room
      final roomData = message.data['room'] ?? _currentRoom?.toJson();
      
      // Emit game started event
      _gameStartedController.add({
        'gameState': message.data['gameState'],
        'message': message.data['message'],
        'room': roomData,
      });
      
      // Handle game state if provided
      if (message.data['gameState'] != null) {
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
      // debug: log raw payload for troubleshooting
      if (kDebugMode) print('🛰️ Received gameStateUpdate (raw): ${message.data}');
      final gameState = MultiplayerGameState.fromJson(message.data['gameState']);
      _currentGameState = gameState;
      _gameStateController.add(gameState);

      if (kDebugMode) {
        print('🛰️ Parsed MultiplayerGameState: phase=${gameState.phase}, contract=${gameState.currentContract}');
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

  void _handleKicked(MultiplayerMessage message) {
    final roomName = message.data['roomName'] ?? 'Unknown Room';
    final reason = message.data['reason'] ?? 'You were kicked from the room';
    
    if (kDebugMode) {
      print('👢 You were kicked from room: $roomName');
      print('   Reason: $reason');
    }
    
    // Clear current room info since we were kicked
    _currentRoom = null;
    _currentRoomId = null;
    _currentGameState = null;
  }

  void _handlePlayerKicked(MultiplayerMessage message) {
    final kickedPlayerName = message.data['kickedPlayerName'];
    final isAI = message.data['isAI'] ?? false;
    final kickedBy = message.data['kickedBy'] ?? 'Host';
    
    if (kDebugMode) {
      print('👢 Player kicked: $kickedPlayerName (${isAI ? 'AI' : 'Human'}) by $kickedBy');
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

  /// Send contract selection to server
  Future<void> selectContract(String contract) async {
    if (!_isConnected || _playerId == null) {
      throw Exception('Not connected or player ID is null');
    }
    
    if (_currentRoom == null) {
      throw Exception('Not in a room');
    }
    
    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'selectContract',
      senderId: _playerId!,
      roomId: _currentRoom!.id,
      data: {
        'roomId': _currentRoom!.id,
        'contract': contract,
        'gameId': _currentRoom!.currentGameId,
      },
      timestamp: DateTime.now(),
    
    );

    _sendMessage(message);
    if (kDebugMode) {
      print('📤 Contract selection sent: $contract');
    }
  }

  /// Send card play to server
  Future<void> playCard(Map<String, dynamic> card) async {
    if (!_isConnected || _playerId == null) {
      throw Exception('Not connected or player ID is null');
    }
    
    if (_currentRoom == null) {
      throw Exception('Not in a room');
    }
    
    final message = MultiplayerMessage(
      id: const Uuid().v4(),
      type: 'playCard',
      senderId: _playerId!,
      roomId: _currentRoom!.id,
      data: {
        'roomId': _currentRoom!.id,
        'card': card,
        'gameId': _currentRoom!.currentGameId,
      },
      timestamp: DateTime.now(),
    );
    
    _sendMessage(message);
    if (kDebugMode) {
      print('📤 Card play sent: ${card['suit']} ${card['rank']}');
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _roomUpdateController.close();
    _gameStateController.close();
    _gameStartedController.close();
    _completers.close();
  }
}
