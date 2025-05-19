import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart'; // For MethodChannel
import 'dart:async'; // For StreamController and Timer
import 'dart:developer' as developer; // For logging

class SensorService {
  static const String _temperatureChannelName = "com.example.water_slosher/temperature";
  final MethodChannel _temperatureChannel = MethodChannel(_temperatureChannelName);
  
  StreamController<double> _temperatureController = StreamController<double>.broadcast();
  Timer? _temperaturePollTimer;

  Stream<AccelerometerEvent> get accelerometerStream => accelerometerEvents;
  Stream<double> get temperatureStream => _temperatureController.stream;

  SensorService() {
    _startPollingTemperature();
  }

  void _startPollingTemperature() {
    // Poll for temperature periodically, e.g., every 5 seconds
    // Adjust the duration as needed, considering battery impact.
    _temperaturePollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _fetchDeviceTemperature();
    });
    // Fetch initial temperature immediately
    _fetchDeviceTemperature();
  }

  Future<void> _fetchDeviceTemperature() async {
    try {
      final double? temperature = await _temperatureChannel.invokeMethod<double>('getDeviceTemperature');
      if (temperature != null) {
        if (!_temperatureController.isClosed) {
          _temperatureController.add(temperature);
        }
      } else {
        developer.log("Received null temperature from native", name: 'SensorService.Temp');
        if (!_temperatureController.isClosed) {
         // _temperatureController.addError("Null temperature received"); // Or a specific error value
        }
      }
    } on PlatformException catch (e) {
      developer.log("Failed to get device temperature: '${e.message}'.", name: 'SensorService.Temp', error: e);
      if (!_temperatureController.isClosed) {
        _temperatureController.addError(e); // Or a specific error value like -999.0
      }
    } catch (e) {
      developer.log("An unexpected error occurred fetching temperature: $e", name: 'SensorService.Temp', error: e);
       if (!_temperatureController.isClosed) {
        _temperatureController.addError(e);
      }
    }
  }

  void start() {
    // Accelerometer starts automatically via sensors_plus
    // Temperature polling starts in constructor
    if (_temperaturePollTimer == null || !_temperaturePollTimer!.isActive) {
      _startPollingTemperature(); // Restart polling if it was stopped
    }
  }
  
  void stop()  {
    // sensors_plus handles accelerometer stream implicitly
    _temperaturePollTimer?.cancel();
    _temperaturePollTimer = null;
    // Don't close the controller here if the service might be started again.
  }

  // Call this when the service is completely disposed.
  void dispose() {
    _temperaturePollTimer?.cancel();
    _temperatureController.close();
    developer.log("SensorService disposed, temperature polling stopped and controller closed.", name: 'SensorService');
  }
}