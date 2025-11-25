import 'dart:async';

class NotificationNavigationService {
  static final NotificationNavigationService _instance = NotificationNavigationService._internal();
  factory NotificationNavigationService() => _instance;
  NotificationNavigationService._internal();

  final StreamController<Map<String, dynamic>> _navigationController = 
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get navigationStream => _navigationController.stream;

  void navigateFromBackground(Map<String, dynamic> data) {
    _navigationController.add(data);
  }

  void dispose() {
    _navigationController.close();
  }
}
