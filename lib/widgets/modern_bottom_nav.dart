import 'package:flutter/material.dart';

/// A modern, animated bottom navigation bar widget
/// Provides navigation between Food Map, Eco Challenges, and Pollution screens
class ModernBottomNav extends StatelessWidget {
  /// The currently selected navigation item index
  final int currentIndex;
  
  /// Callback function triggered when a navigation item is tapped
  final Function(int) onTap;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 65,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context,
            index: 0,
            icon: Icons.map,
            label: 'Food Map',
            color: const Color(0xFF00A74C),
          ),
          _buildNavItem(
            context,
            index: 1,
            icon: Icons.eco,
            label: 'Eco Challenges',
            color: Colors.green[600]!,
          ),
          _buildNavItem(
            context,
            index: 2,
            icon: Icons.report_problem,
            label: 'Pollution',
            color: Colors.red[700]!,
          ),
        ],
      ),
    );
  }

  /// Builds an individual navigation item with icon and label
  /// Includes animation and visual feedback for selected state
  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: color.withOpacity(0.3), width: 2)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? color : color.withOpacity(0.5),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : color.withOpacity(0.5),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 