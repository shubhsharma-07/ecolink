import 'package:flutter/material.dart';

class TabPageTransition extends PageRouteBuilder {
  final Widget page;
  final int fromIndex;
  final int toIndex;

  TabPageTransition({
    required this.page,
    required this.fromIndex,
    required this.toIndex,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Determine the direction of the transition
            final bool isForward = toIndex > fromIndex;
            
            // Create a slide transition
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(isForward ? 1.0 : -1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              )),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
} 