import 'package:flutter/foundation.dart';

/// Simplified GameProvider for testing
class GameProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  
  // Basic getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveGame => false;
  bool get isHumanPlayerTurn => false;
  bool get isMultiplayerGame => false;
  bool get shouldHighlightCards => false;
  bool get canHumanPlayerPass => false;
  bool get isLoggingEnabled => false;
  bool get isLightweightAIMode => false;
  
  dynamic get game => null;
  dynamic get currentUser => null;
  dynamic get humanPlayerPosition => null;
  
  List<dynamic> getValidCardsForHuman() => [];
  
  void passTrexTurn() {}
  void doubleKingOfHearts() {}
  Future<void> setLoggingEnabled(bool enabled) async {}
  Future<String?> exportTrainingData() async => null;
  Future<String?> getLogsDirectory() async => null;
  Future<void> reinitializeAIService() async {}
  Future<Map<String, dynamic>> testAIConnection() async => {'success': false};
  
  void selectContract(dynamic contract) {}
  void playCard(dynamic card) {}
  void resetGame() {}
  void clearError() {}
}
