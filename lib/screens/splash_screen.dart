import 'package:flutter/material.dart';

const Color kGreen = Color(0xFF00A74C);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: Theme.of(context).brightness == Brightness.dark
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kGreen.withOpacity(0.85),
                    kGreen,
                    kGreen,
                  ],
                ),
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.background
              : null,
        ),
        child: Center(
          child: Image.asset(
            'assets/logonobg.png',
            width: 200,
            height: 200,
          ),
        ),
      ),
    );
  }
} 