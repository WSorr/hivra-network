import 'package:flutter/material.dart';
import '../models/invitation.dart';

class InvitationCard extends StatelessWidget {
  final Invitation invitation;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final bool isLoading;

  const InvitationCard({
    super.key,
    required this.invitation,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: invitation.kind.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  invitation.kind.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: invitation.status.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    invitation.status.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: invitation.status.color,
                    ),
                  ),
                ),
                const Spacer(),
                if (invitation.isIncoming)
                  const Icon(Icons.arrow_downward, size: 16, color: Colors.grey)
                else
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.grey),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invitation.isIncoming ? 'From:' : 'To:',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        invitation.isIncoming
                            ? invitation.fromPubkey
                            : invitation.toPubkey!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (invitation.starterSlot != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Slot ${invitation.starterSlot! + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Time
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(invitation.sentAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (invitation.expiresAt != null) ...[
                  const SizedBox(width: 8),
                  if (invitation.isExpired)
                    const Icon(
                      Icons.warning,
                      size: 14,
                      color: Colors.orange,
                    )
                  else
                    const Icon(
                      Icons.hourglass_empty,
                      size: 14,
                      color: Colors.grey,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    'Expires ${_formatDate(invitation.expiresAt!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: invitation.isExpired
                          ? Colors.orange
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
            
            if (invitation.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning,
                      size: 16,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        invitation.rejectionReason!.displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Actions
            if (invitation.status == InvitationStatus.pending && !invitation.isExpired) ...[
              const SizedBox(height: 16),
              if (invitation.isIncoming)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isLoading ? null : onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isLoading ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative) {
      final future = date.difference(now);
      if (future.inMinutes < 60) {
        return 'in ${future.inMinutes} minutes';
      } else if (future.inHours < 24) {
        return 'in ${future.inHours} hours';
      }
      return 'in ${future.inDays} days';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }
}
