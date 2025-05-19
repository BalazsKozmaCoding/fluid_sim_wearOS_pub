import 'package:flutter/services.dart';
import 'dart:async';

class BezelChannelService {
  static const MethodChannel _channel =
      MethodChannel('com.example.water_slosher/bezel'); // Must match native

  final StreamController<double> _bezelEventsController =
      StreamController<double>.broadcast();
  bool _firstBezelEventSkipped = false; // Added flag

  Stream<double> get bezelEvents => _bezelEventsController.stream;

  BezelChannelService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onBezelScroll') {
      final double? delta = call.arguments['delta'] as double?;
      if (delta != null) {
        if (!_firstBezelEventSkipped) {
          _firstBezelEventSkipped = true;
          return; // Skip the first event
        }
        _bezelEventsController.add(delta);
      }
    }
  }

  void dispose() {
    _bezelEventsController.close();
  }
}