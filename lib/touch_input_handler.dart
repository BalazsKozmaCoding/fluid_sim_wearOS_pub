import 'package:flutter/gestures.dart';

import 'package:flutter/gestures.dart';

class TouchInputHandler {
  double obstacleX = 0.0, obstacleY = 0.0;
  double obstacleVelX = 0.0, obstacleVelY = 0.0;

  // Simulation dimensions will be needed for scaling
  final double simWidth;
  final double simHeight;

  TouchInputHandler({required this.simWidth, required this.simHeight});

  // Methods to update obstacle state based on mapped simulation coordinates and velocity
  void updateObstaclePosition(double x, double y) {
    obstacleX = x;
    obstacleY = y;
  }

  void updateObstacleVelocity(double vx, double vy) {
    obstacleVelX = vx;
    obstacleVelY = vy;
  }

  void resetObstacleVelocity() {
    obstacleVelX = 0.0;
    obstacleVelY = 0.0;
  }
}