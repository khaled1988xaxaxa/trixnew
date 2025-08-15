import 'package:flutter/foundation.dart';

/// Simple test version of GameProvider to check compilation
class GameProviderTest with ChangeNotifier {
  bool _isLoading = false;
  
  bool get isLoading => _isLoading;
  
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
