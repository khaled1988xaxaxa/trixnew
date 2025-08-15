import 'player.dart';
import 'card.dart';
import 'game.dart';

/// Connection status for multiplayer service
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  noInternet,
}

/// Multiplayer room/table model
class GameRoom {
  final String id;
  final String name;
  final String hostId;
  final List<PlayerSession> players;
  final GameRoomStatus status;
  final DateTime createdAt;
  final GameRoomSettings settings;
  TrexGame? currentGame;
  String? currentGameId;

  GameRoom({
    required this.id,
    required this.name,
    required this.hostId,
    List<PlayerSession>? players,
    this.status = GameRoomStatus.waiting,
    DateTime? createdAt,
    this.settings = const GameRoomSettings(),
    this.currentGame,
    this.currentGameId,
  }) : players = players ?? [],
       createdAt = createdAt ?? DateTime.now();

  bool get isFull => players.length >= 4;
  bool get canStart => isFull && status == GameRoomStatus.waiting;
  bool get isActive => status == GameRoomStatus.playing;
  
  PlayerSession? getHost() {
    try {
      return players.firstWhere((p) => p.id == hostId);
    } catch (e) {
      return null;
    }
  }

  PlayerSession? getPlayerById(String playerId) {
    try {
      return players.firstWhere((p) => p.id == playerId);
    } catch (e) {
      return null;
    }
  }

  bool isPlayerInRoom(String playerId) {
    return players.any((p) => p.id == playerId);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hostId': hostId,
      'players': players.map((p) => p.toJson()).toList(),
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'settings': settings.toJson(),
      'currentGameId': currentGameId,
    };
  }

  factory GameRoom.fromJson(Map<String, dynamic> json) {
    return GameRoom(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Room',
      hostId: json['hostId']?.toString() ?? '',
      players: (json['players'] as List? ?? [])
          .map((p) => PlayerSession.fromJson(p))
          .toList(),
      status: GameRoomStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => GameRoomStatus.waiting,
      ),
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      settings: GameRoomSettings.fromJson(json['settings'] ?? {}),
      currentGameId: json['currentGameId']?.toString(),
    );
  }
}

/// Player session in multiplayer
class PlayerSession {
  final String id;
  final String name;
  final String? avatarUrl;
  final PlayerPosition position;
  final PlayerSessionStatus status;
  final DateTime joinedAt;
  final DateTime? lastSeen;
  bool isReady;
  bool isHost;
  final bool isAI;

  PlayerSession({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.position,
    this.status = PlayerSessionStatus.connected,
    DateTime? joinedAt,
    this.lastSeen,
    this.isReady = false,
    this.isHost = false,
    this.isAI = false,
  }) : joinedAt = joinedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'position': position.name,
      'status': status.name,
      'joinedAt': joinedAt.toIso8601String(),
      'lastSeen': lastSeen?.toIso8601String(),
      'isReady': isReady,
      'isHost': isHost,
      'isAI': isAI,
    };
  }

  factory PlayerSession.fromJson(Map<String, dynamic> json) {
    return PlayerSession(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Player',
      avatarUrl: json['avatarUrl']?.toString(),
      position: PlayerPosition.values.firstWhere(
        (e) => e.name == json['position'],
        orElse: () => PlayerPosition.south,
      ),
      status: PlayerSessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PlayerSessionStatus.connected,
      ),
      joinedAt: json['joinedAt'] != null 
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
      lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen']) : null,
      isReady: json['isReady'] ?? false,
      isHost: json['isHost'] ?? false,
      isAI: json['isAI'] ?? false,
    );
  }

  PlayerSession copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    PlayerPosition? position,
    PlayerSessionStatus? status,
    DateTime? joinedAt,
    DateTime? lastSeen,
    bool? isReady,
    bool? isHost,
    bool? isAI,
  }) {
    return PlayerSession(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      position: position ?? this.position,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isReady: isReady ?? this.isReady,
      isHost: isHost ?? this.isHost,
      isAI: isAI ?? this.isAI,
    );
  }
}

/// Game room settings
class GameRoomSettings {
  final bool allowSpectators;
  final bool autoStart;
  final int maxPlayers;
  final bool allowAI;
  final int aiCount;
  final bool enableChat;
  final bool enableVoice;
  final String? password;

  const GameRoomSettings({
    this.allowSpectators = false,
    this.autoStart = true,
    this.maxPlayers = 4,
    this.allowAI = true,
    this.aiCount = 0,
    this.enableChat = true,
    this.enableVoice = false,
    this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'allowSpectators': allowSpectators,
      'autoStart': autoStart,
      'maxPlayers': maxPlayers,
      'allowAI': allowAI,
      'aiCount': aiCount,
      'enableChat': enableChat,
      'enableVoice': enableVoice,
      'password': password,
    };
  }

  factory GameRoomSettings.fromJson(Map<String, dynamic> json) {
    return GameRoomSettings(
      allowSpectators: json['allowSpectators'] ?? false,
      autoStart: json['autoStart'] ?? true,
      maxPlayers: json['maxPlayers'] ?? 4,
      allowAI: json['allowAI'] ?? true,
      aiCount: json['aiCount'] ?? 0,
      enableChat: json['enableChat'] ?? true,
      enableVoice: json['enableVoice'] ?? false,
      password: json['password'],
    );
  }
}

/// Multiplayer game state for synchronization
class MultiplayerGameState {
  final String gameId;
  final String roomId;
  final GamePhase phase;
  final TrexContract? currentContract;
  final PlayerPosition currentPlayer;
  final PlayerPosition currentKing;
  final int round;
  final int kingdom;
  final Map<PlayerPosition, int> scores;
  final Map<PlayerPosition, List<Card>> playerHands;
  final Trick? currentTrick;
  final List<Trick> completedTricks;
  final DateTime lastUpdated;
  final Map<String, dynamic> metadata;

  MultiplayerGameState({
    required this.gameId,
    required this.roomId,
    required this.phase,
    this.currentContract,
    required this.currentPlayer,
    required this.currentKing,
    required this.round,
    required this.kingdom,
    required this.scores,
    required this.playerHands,
    this.currentTrick,
    List<Trick>? completedTricks,
    DateTime? lastUpdated,
    Map<String, dynamic>? metadata,
  }) : completedTricks = completedTricks ?? [],
       lastUpdated = lastUpdated ?? DateTime.now(),
       metadata = metadata ?? {};

  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'roomId': roomId,
      'phase': phase.name,
      'currentContract': currentContract?.name,
      'currentPlayer': currentPlayer.name,
      'currentKing': currentKing.name,
      'round': round,
      'kingdom': kingdom,
      'scores': scores.map((key, value) => MapEntry(key.name, value)),
      'playerHands': playerHands.map((key, value) => 
          MapEntry(key.name, value.map((c) => c.toJson()).toList())),
      'currentTrick': currentTrick?.toJson(),
      'completedTricks': completedTricks.map((t) => t.toJson()).toList(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory MultiplayerGameState.fromJson(Map<String, dynamic> json) {
    return MultiplayerGameState(
      gameId: json['gameId'],
      roomId: json['roomId'],
      phase: GamePhase.values.firstWhere(
        (e) => e.name == json['phase'],
        orElse: () => GamePhase.contractSelection,
      ),
      currentContract: json['currentContract'] != null
          ? TrexContract.values.firstWhere(
              (e) => e.name == json['currentContract'],
              orElse: () => TrexContract.kingOfHearts,
            )
          : null,
      currentPlayer: PlayerPosition.values.firstWhere(
        (e) => e.name == json['currentPlayer'],
        orElse: () => PlayerPosition.south,
      ),
      currentKing: PlayerPosition.values.firstWhere(
        (e) => e.name == json['currentKing'],
        orElse: () => PlayerPosition.south,
      ),
      round: json['round'] ?? 1,
      kingdom: json['kingdom'] ?? 1,
      scores: (json['scores'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          PlayerPosition.values.firstWhere((e) => e.name == key),
          value as int,
        ),
      ),
      playerHands: (json['playerHands'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          PlayerPosition.values.firstWhere((e) => e.name == key),
          (value as List).map((c) => Card.fromJson(c)).toList(),
        ),
      ),
      currentTrick: json['currentTrick'] != null
          ? Trick.fromJson(json['currentTrick'])
          : null,
      completedTricks: (json['completedTricks'] as List?)
          ?.map((t) => Trick.fromJson(t))
          .toList() ?? [],
      lastUpdated: DateTime.parse(json['lastUpdated']),
      metadata: json['metadata'] ?? {},
    );
  }
}

/// Multiplayer message types
class MultiplayerMessage {
  final String id;
  final String type;
  final String senderId;
  final String roomId;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  MultiplayerMessage({
    required this.id,
    required this.type,
    required this.senderId,
    required this.roomId,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'senderId': senderId,
      'roomId': roomId,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MultiplayerMessage.fromJson(Map<String, dynamic> json) {
    return MultiplayerMessage(
      id: json['id'],
      type: json['type'],
      senderId: json['senderId'],
      roomId: json['roomId'],
      data: json['data'] ?? {},
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Enums for multiplayer
enum GameRoomStatus {
  waiting,
  playing,
  finished,
  paused,
}

enum PlayerSessionStatus {
  connected,
  disconnected,
  spectating,
  ready,
  playing,
}

/// Message types for multiplayer communication
enum MessageType {
  // Room management
  joinRoom,
  leaveRoom,
  createRoom,
  roomUpdate,
  playerJoined,
  playerLeft,
  playerReady,
  
  // Game management
  startGame,
  endGame,
  gameStateUpdate,
  cardPlayed,
  contractSelected,
  
  // Chat and communication
  chatMessage,
  voiceMessage,
  
  // System messages
  error,
  ping,
  pong,
  reconnect,
}
