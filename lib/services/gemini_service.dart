import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Service class that handles AI-powered image analysis using Google's Gemini API
/// Provides functionality for analyzing food and pollution images
class GeminiService {
  static const String _apiKey = 'AIzaSyDmwjPVHKc9xMJfUulhr_0pvEjcLyFs-_E';
  late final GenerativeModel _model;
  late final GenerativeModel _visionModel;

  /// Initializes the Gemini service with appropriate models
  /// Sets up both text and vision models for different use cases
  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-pro',
      apiKey: _apiKey,
    );
    _visionModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  /// Analyzes an image to identify and describe food items
  /// Returns structured information about detected food
  Future<Map<String, dynamic>> analyzeFoodImage(File imageFile) async {
    try {
      print('Starting image analysis...');
      final bytes = await imageFile.readAsBytes();
      
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
      );

      final prompt = '''
Analyze this image and provide information about any food items present. 
Include packaged food items, prepared meals, or raw ingredients.
If no food is detected, respond with "NO_FOOD_DETECTED".

Provide the response in the following JSON format:
{
  "name": "Name of the food item",
  "description": "Brief description of the food",
  "characteristics": "Key characteristics like taste, texture, etc.",
  "isFood": true/false
}

If multiple food items are present, focus on the most prominent one.
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ]),
      ];

      print('Sending request to Gemini API...');
      final response = await model.generateContent(content);
      print('Received response from Gemini API');
      
      if (response.text == null) {
        print('No response text received');
        throw Exception('No response from AI service');
      }

      print('Response text: ${response.text}');
      
      // Extract JSON from the response
      final jsonStr = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
      print('Extracted JSON string: $jsonStr');
      
      final Map<String, dynamic> analysis = json.decode(jsonStr);
      print('Parsed analysis: $analysis');

      // Check if no food was detected
      if (analysis['isFood'] == false || analysis['name'] == 'NO_FOOD_DETECTED') {
        return {
          'name': 'NO_FOOD_DETECTED',
          'description': 'No food items were detected in the image.',
          'characteristics': '',
          'isFood': false
        };
      }

      return {
        'name': analysis['name'] ?? 'Unknown Food',
        'description': analysis['description'] ?? 'No description available',
        'characteristics': analysis['characteristics'] ?? 'No characteristics available',
        'isFood': true
      };
    } catch (e) {
      print('Error in analyzeFoodImage: $e');
      return {
        'name': 'Error',
        'description': 'Failed to analyze image: $e',
        'characteristics': '',
        'isFood': false
      };
    }
  }

  /// Analyzes an image to detect and assess environmental pollution
  /// Returns structured information about pollution type and severity
  Future<Map<String, dynamic>> analyzePollutionImage(File imageFile) async {
    try {
      print('Starting pollution image analysis...');
      final bytes = await imageFile.readAsBytes();
      
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
      );

      final prompt = '''
Analyze this image for any signs of pollution or environmental damage. Look for:
- Air pollution (smog, smoke, haze, emissions)
- Water pollution (contaminated water, oil spills, debris in water)
- Noise pollution (loud machinery, construction, traffic)
- Littering/Trash (garbage, litter, waste)
- Chemical spills (hazardous materials, chemical contamination)
- Light pollution (excessive artificial lighting)
- Soil contamination (damaged land, chemical residue)
- Other environmental issues

If no pollution is detected, respond with "NO_POLLUTION_DETECTED".

Provide the response in the following JSON format:
{
  "pollutionType": "One of: Air Pollution, Water Pollution, Noise Pollution, Littering/Trash, Chemical Spill, Light Pollution, Soil Contamination, Other",
  "severity": "One of: Low, Medium, High, Critical",
  "description": "Detailed description of the pollution issue observed",
  "isPollution": true/false
}

Base severity on:
- Low: Minor issues, small scale
- Medium: Moderate issues, localized impact
- High: Significant issues, broader impact
- Critical: Severe issues, immediate action needed
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ]),
      ];

      print('Sending request to Gemini API for pollution analysis...');
      final response = await model.generateContent(content);
      print('Received pollution analysis response from Gemini API');
      
      if (response.text == null) {
        print('No response text received');
        throw Exception('No response from AI service');
      }

      print('Response text: ${response.text}');
      
      // Extract JSON from the response
      final jsonStr = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
      print('Extracted JSON string: $jsonStr');
      
      final Map<String, dynamic> analysis = json.decode(jsonStr);
      print('Parsed analysis: $analysis');

      // Check if no pollution was detected
      if (analysis['isPollution'] == false || analysis['pollutionType'] == 'NO_POLLUTION_DETECTED') {
        return {
          'pollutionType': 'NO_POLLUTION_DETECTED',
          'severity': 'Low',
          'description': 'No pollution was detected in the image.',
          'isPollution': false
        };
      }

      return {
        'pollutionType': analysis['pollutionType'] ?? 'Other',
        'severity': analysis['severity'] ?? 'Low',
        'description': analysis['description'] ?? 'No description available',
        'isPollution': true
      };
    } catch (e) {
      print('Error in analyzePollutionImage: $e');
      return {
        'pollutionType': 'Error',
        'severity': 'Low',
        'description': 'Failed to analyze image: $e',
        'isPollution': false
      };
    }
  }
}