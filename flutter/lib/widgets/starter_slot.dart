import 'package:flutter/material.dart';
import '../models/starter.dart';

class StarterSlot extends StatelessWidget {
  final int index;
  final Starter? starter;
  final VoidCallback? onTap;
  final bool isLoading;

  const StarterSlot({
    super.key,
    required this.index,
    this.starter,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Slot index
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Starter details
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : starter != null
                        ? _buildStarterInfo(context, starter!)
                        : _buildEmptySlot(context),
              ),
              
              const SizedBox(width: 8),
              
              // Navigation indicator
              if (onTap != null)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarterInfo(BuildContext context, Starter starter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: starter.kind.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              starter.kind.displayName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            if (starter.state != StarterState.active)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: starter.state == StarterState.burned
                      ? Colors.red.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  starter.state.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    color: starter.state == StarterState.burned
                        ? Colors.red.shade900
                        : Colors.orange.shade900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'ID: ${_starterIdPreview(starter.id)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          'Created: ${_formatDate(starter.createdAt)}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildEmptySlot(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Empty Slot',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Tap to create or import starter',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  String _starterIdPreview(String id) {
    if (id.isEmpty) return 'unknown';
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}...';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return 'Just now';
    }
  }
}
