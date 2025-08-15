import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_provider.dart';
import '../models/multiplayer_models.dart';
import '../services/multiplayer_service.dart';

class MultiplayerLobbyScreen extends StatefulWidget {
  const MultiplayerLobbyScreen({super.key});

  @override
  State<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends State<MultiplayerLobbyScreen> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isCreatingRoom = false;
  bool _isJoiningRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMultiplayer();
    });
  }

  Future<void> _initializeMultiplayer() async {
    final multiplayerProvider = Provider.of<MultiplayerProvider>(context, listen: false);
    await multiplayerProvider.initialize();
    await multiplayerProvider.connect();
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('غرف اللعب المتعددة'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          Consumer<MultiplayerProvider>(
            builder: (context, provider, child) {
              return _buildConnectionStatus(provider);
            },
          ),
        ],
      ),
      body: Consumer<MultiplayerProvider>(
        builder: (context, provider, child) {
          if (provider.isConnecting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري الاتصال بالخادم...'),
                ],
              ),
            );
          }

          if (!provider.isConnected) {
            return _buildConnectionError(provider);
          }

          return Column(
            children: [
              _buildHeader(provider),
              Expanded(
                child: _buildRoomsList(provider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateRoomDialog,
        label: const Text('إنشاء غرفة'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildConnectionStatus(MultiplayerProvider provider) {
    IconData icon;
    Color color;

    switch (provider.connectionStatus) {
      case ConnectionStatus.connected:
        icon = Icons.wifi;
        color = Colors.green;
        break;
      case ConnectionStatus.connecting:
        icon = Icons.wifi_find;
        color = Colors.orange;
        break;
      case ConnectionStatus.disconnected:
        icon = Icons.wifi_off;
        color = Colors.red;
        break;
      case ConnectionStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
      case ConnectionStatus.noInternet:
        icon = Icons.signal_wifi_off;
        color = Colors.red;
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildConnectionError(MultiplayerProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.wifi_off,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            'لا يمكن الاتصال بالخادم',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (provider.errorMessage != null)
            Text(
              provider.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => provider.connect(),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MultiplayerProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الغرف المتاحة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${provider.availableRooms.length} غرفة متاحة',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => provider.getAvailableRooms(),
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsList(MultiplayerProvider provider) {
    if (provider.availableRooms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.meeting_room_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'لا توجد غرف متاحة',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'قم بإنشاء غرفة جديدة أو انتظر حتى ينشئ شخص آخر غرفة',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: provider.availableRooms.length,
      itemBuilder: (context, index) {
        final room = provider.availableRooms[index];
        return _buildRoomCard(room, provider);
      },
    );
  }

  Widget _buildRoomCard(GameRoom room, MultiplayerProvider provider) {
    final isFull = room.isFull;
    final canJoin = !isFull && room.status == GameRoomStatus.waiting;
    final isInRoom = provider.currentRoom?.id == room.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isInRoom ? Colors.green : Colors.blue,
          child: Icon(
            isInRoom ? Icons.check : Icons.meeting_room,
            color: Colors.white,
          ),
        ),
        title: Text(
          room.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اللاعبون: ${room.players.length}/${room.settings.maxPlayers}'),
            Text('الحالة: ${_getRoomStatusText(room.status)}'),
            if (room.settings.password != null)
              const Text('🔒 محمية بكلمة مرور', style: TextStyle(color: Colors.orange)),
            Text('المضيف: ${room.getHost()?.name ?? 'غير معروف'}'),
          ],
        ),
        trailing: isInRoom
            ? const Chip(
                label: Text('أنت هنا'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white),
              )
            : canJoin
                ? ElevatedButton(
                    onPressed: () => _showJoinRoomDialog(room),
                    child: const Text('انضم'),
                  )
                : const Chip(
                    label: Text('ممتلئة'),
                    backgroundColor: Colors.grey,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
        onTap: isInRoom ? () => _navigateToRoom(room) : null,
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
        return 'منتهية';
      case GameRoomStatus.paused:
        return 'متوقفة مؤقتاً';
    }
  }

  void _showCreateRoomDialog() {
    _roomNameController.clear();
    _passwordController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء غرفة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: 'اسم الغرفة',
                hintText: 'أدخل اسم الغرفة',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور (اختياري)',
                hintText: 'اتركها فارغة إذا لم ترد حماية',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isCreatingRoom ? null : _createRoom,
            child: _isCreatingRoom
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم الغرفة')),
      );
      return;
    }

    setState(() {
      _isCreatingRoom = true;
    });

    try {
      final provider = Provider.of<MultiplayerProvider>(context, listen: false);
      final settings = GameRoomSettings(
        password: _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text.trim(),
      );

      final room = await provider.createRoom(
        name: _roomNameController.text.trim(),
        settings: settings,
      );

      if (room != null) {
        Navigator.of(context).pop(); // Close dialog
        _navigateToRoom(room);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في إنشاء الغرفة')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      setState(() {
        _isCreatingRoom = false;
      });
    }
  }

  void _showJoinRoomDialog(GameRoom room) {
    _passwordController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('انضم إلى ${room.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room.settings.password != null) ...[
              const Text('هذه الغرفة محمية بكلمة مرور'),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  hintText: 'أدخل كلمة المرور',
                ),
                obscureText: true,
              ),
            ] else ...[
              const Text('انقر على "انضم" للانضمام إلى هذه الغرفة'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isJoiningRoom ? null : () => _joinRoom(room),
            child: _isJoiningRoom
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('انضم'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinRoom(GameRoom room) async {
    if (room.settings.password != null && _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال كلمة المرور')),
      );
      return;
    }

    setState(() {
      _isJoiningRoom = true;
    });

    try {
      final provider = Provider.of<MultiplayerProvider>(context, listen: false);
      final success = await provider.joinRoom(
        room.id,
        password: room.settings.password != null ? _passwordController.text.trim() : null,
      );

      if (success) {
        Navigator.of(context).pop(); // Close dialog
        _navigateToRoom(room);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في الانضمام إلى الغرفة')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      setState(() {
        _isJoiningRoom = false;
      });
    }
  }

  void _navigateToRoom(GameRoom room) {
    Navigator.of(context).pushNamed('/multiplayer-room', arguments: room);
  }
}
