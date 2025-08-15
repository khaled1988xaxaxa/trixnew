import 'package:flutter/material.dart';
import 'lib/providers/game_provider.dart';

void main() {
  final provider = GameProvider();
  print('GameProvider created successfully');
  print('Has active game: ${provider.hasActiveGame}');
}
