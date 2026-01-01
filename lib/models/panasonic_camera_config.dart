import 'package:flutter/material.dart';
import '../services/panasonic_service.dart';

// Configuration class for Panasonic cameras
class PanasonicCameraConfig {
  final String name;
  final TextEditingController ipController;
  PanasonicService? service;
  bool isConnected = false;
  bool isConnecting = false;
  String connectionError = '';
  
  PanasonicCameraConfig({
    required this.name,
    required String ipAddress,
  }) : ipController = TextEditingController(text: ipAddress);
}