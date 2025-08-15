import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/multiplayer_provider.dart';
import '../models/multiplayer_models.dart';

class MultiplayerRoomScreen extends StatefulWidget {
  const MultiplayerRoomScreen({Key? key}) : super(key: key);

  @override
  State<MultiplayerRoomScreen> createState() => _MultiplayerRoomScreenState();
}

class _MultiplayerRoomScreenState extends State<MultiplayerRoomScreen> {
  late GameRoom room;
  final TextEditingController _chatController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _gameStartedSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    room = ModalRoute.of(context)!.settings.arguments as GameRoom;
  }

  @override
  void initState() {
    super.initState();
    
    // Listen to game started events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<MultiplayerProvider>(context, listen: false);
      _gameStartedSubscription = provider.gameStartedStream.listen((gameStartData) {
        if (mounted) {
          // Navigate to game screen
          Navigator.of(context).pushReplacementNamed(
            '/game',
            arguments: {
              'isMultiplayer': true,
              'room': gameStartData['room'],
              'gameState': gameStartData['gameState'],
            },
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _gameStartedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('غرفة: ${room.name}'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: _leaveRoom,
            tooltip: 'مغادرة الغرفة',
          ),
        ],
      ),
      body: Consumer<MultiplayerProvider>(
        builder: (context, provider, child) {
          final currentRoom = provider.currentRoom ?? room;
          
          return Column(
            children: [
              // Room Status Header
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'غرفة: ${currentRoom.name}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اللاعبون: ${currentRoom.players.length}/${currentRoom.settings.maxPlayers}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      'الحالة: ${_getRoomStatusText(currentRoom.status)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),

              // Players List
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'اللاعبون',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: currentRoom.players.length,
                          itemBuilder: (context, index) {
                            final player = currentRoom.players[index];
                            final currentPlayerSession = provider.getCurrentPlayerSession();
                            final isCurrentPlayerHost = currentPlayerSession?.isHost ?? false;
                            final isPlayerHost = player.id == currentRoom.hostId; // Check if this player is the actual host
                            final canKick = isCurrentPlayerHost && !isPlayerHost; // Host can kick non-hosts
                            
                            // Debug prints
                            print('🔍 Debug player ${player.name}:');
                            print('   - player.id: ${player.id}');
                            print('   - room.hostId: ${currentRoom.hostId}');
                            print('   - isPlayerHost: $isPlayerHost');
                            print('   - isAI: ${player.isAI}');
                            print('   - currentPlayerIsHost: $isCurrentPlayerHost');
                            print('   - canKick: $canKick');
                            print('🔍 Debug current player session:');
                            print('   - currentPlayerSession: ${currentPlayerSession?.name}');
                            print('   - currentPlayerSession.id: ${currentPlayerSession?.id}');
                            print('   - currentPlayerSession.isHost: ${currentPlayerSession?.isHost}');
                            print('   - room.hostId: ${currentRoom.hostId}');
                            print('   - service.playerId: ${provider.playerId}');
                            
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPlayerHost 
                                    ? Colors.amber 
                                    : player.isAI
                                      ? Colors.blue
                                      : Theme.of(context).primaryColor,
                                  child: Icon(
                                    isPlayerHost 
                                      ? Icons.star 
                                      : player.isAI
                                        ? Icons.smart_toy
                                        : Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(player.name),
                                subtitle: Text(
                                  isPlayerHost 
                                    ? 'مضيف الغرفة' 
                                    : player.isAI
                                      ? 'ذكاء اصطناعي'
                                      : 'لاعب',
                                  style: TextStyle(
                                    color: isPlayerHost 
                                      ? Colors.amber 
                                      : player.isAI
                                        ? Colors.blue
                                        : null,
                                  ),
                                ),
                                trailing: SizedBox(
                                  width: canKick ? 80 : 40,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Ready status icon
                                      player.isReady
                                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                          : const Icon(Icons.access_time, color: Colors.orange, size: 18),
                                      
                                      // Kick button - show for non-host players when current player is host
                                      if (canKick) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                          onPressed: () => _showKickDialog(context, provider, player),
                                          tooltip: 'طرد اللاعب',
                                          iconSize: 18,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Ready/Start Button
              if (currentRoom.status == GameRoomStatus.waiting)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canStartGame(currentRoom) ? _startGame : _toggleReady,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canStartGame(currentRoom) 
                          ? Colors.green 
                          : Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        _getButtonText(currentRoom),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

              // Chat Section (Placeholder for now)
              Container(
                height: 200,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chat, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'المحادثة',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'المحادثة ستكون متاحة قريباً',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getRoomStatusText(GameRoomStatus status) {
    switch (status) {
      case GameRoomStatus.waiting:
        return 'في انتظار اللاعبين';
      case GameRoomStatus.playing:
        return 'جاري اللعب';
      case GameRoomStatus.finished:
        return 'انتهت اللعبة';
      case GameRoomStatus.paused:
        return 'متوقفة مؤقتاً';
    }
  }

  bool _canStartGame(GameRoom room) {
    final provider = Provider.of<MultiplayerProvider>(context, listen: false);
    return room.players.length >= 2 && // At least 2 players for testing
           provider.isHost && 
           room.players.every((p) => p.isReady || p.isHost);
  }

  String _getButtonText(GameRoom room) {
    final provider = Provider.of<MultiplayerProvider>(context, listen: false);
    
    if (_canStartGame(room)) {
      return 'بدء اللعبة';
    } else if (provider.isHost) {
      return 'في انتظار اللاعبين';
    } else {
      final currentPlayer = provider.getCurrentPlayerSession();
      if (currentPlayer?.isReady == true) {
        return 'جاهز - في انتظار المضيف';
      } else {
        return 'جاهز';
      }
    }
  }

  void _toggleReady() async {
    final provider = Provider.of<MultiplayerProvider>(context, listen: false);
    if (!provider.isHost) {
      // Toggle ready status for non-host players
      final currentPlayer = provider.getCurrentPlayerSession();
      final newReadyStatus = !(currentPlayer?.isReady ?? false);
      await provider.setReady(newReadyStatus);
    }
  }

  void _showKickDialog(BuildContext context, MultiplayerProvider provider, PlayerSession player) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('طرد ${player.name}'),
          content: Text(
            player.isAI 
              ? 'هل تريد إزالة هذا البوت لإفساح المجال للاعبين الآخرين؟'
              : 'هل أنت متأكد من أنك تريد طرد هذا اللاعب من الغرفة؟'
          ),
          actions: [
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                player.isAI ? 'إزالة البوت' : 'طرد اللاعب',
                style: const TextStyle(color: Colors.red),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                
                final success = await provider.kickPlayer(player.id);
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('فشل في ${player.isAI ? 'إزالة البوت' : 'طرد اللاعب'}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم ${player.isAI ? 'إزالة البوت' : 'طرد اللاعب'} بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _startGame() async {
    final provider = Provider.of<MultiplayerProvider>(context, listen: false);
    if (provider.isHost) {
      final success = await provider.startGame();
      
      if (success && mounted) {
        // Navigate to game screen
        Navigator.of(context).pushReplacementNamed(
          '/game',
          arguments: {
            'isMultiplayer': true,
            'room': provider.currentRoom,
            'gameState': null, // Will be provided by server
          },
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'فشل في بدء اللعبة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _leaveRoom() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة الغرفة'),
        content: const Text('هل أنت متأكد من مغادرة الغرفة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('مغادرة'),
          ),
        ],
      ),
    );

    if (shouldLeave == true) {
      final provider = Provider.of<MultiplayerProvider>(context, listen: false);
      await provider.leaveRoom();
      Navigator.of(context).pop();
    }
  }
}
