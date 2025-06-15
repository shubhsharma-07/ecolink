#!/bin/bash

# Kill any existing adb server
adb kill-server

# Start adb server
adb start-server

# Uninstall existing app
adb uninstall com.example.hackathon

# Clean Flutter
flutter clean

# Get dependencies
flutter pub get

# Run the app
flutter run 