import 'package:flutter/material.dart';
import '../services/panasonic_service.dart';

// Configuration class for Panasonic cameras
class PanasonicCameraConfig {
  final String name;
  final TextEditingController ipController;
  PanasonicService? service;
  ValueNotifier<bool> isConnected = ValueNotifier(false);
  ValueNotifier<bool> isConnecting = ValueNotifier(false);
  ValueNotifier<String> connectionError = ValueNotifier('');
  
  PanasonicCameraConfig({
    required this.name,
    required String ipAddress,
  }) : ipController = TextEditingController(text: ipAddress);
}