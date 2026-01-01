import 'package:flutter/material.dart';
import '../services/abstract/panasonic_service_abstract.dart';

// Configuration class for Panasonic cameras
class PanasonicCameraConfig {
  final String name;
  final TextEditingController ipController;
  PanasonicServiceAbstract? service;
  ValueNotifier<bool> isConnected = ValueNotifier(false);
  ValueNotifier<bool> isConnecting = ValueNotifier(false);
  ValueNotifier<String> connectionError = ValueNotifier('');
  
  PanasonicCameraConfig({
    required this.name,
    required String ipAddress,
    this.service,
  }) : ipController = TextEditingController(text: ipAddress);
}