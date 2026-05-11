import 'package:flutter/material.dart';

import '../models/reading_settings.dart';

@immutable
class FloatingProgressHudData {
  final String title;
  final String message;
  final double? progress;
  final VoidCallback? onCancel;

  const FloatingProgressHudData({
    required this.title,
    required this.message,
    this.progress,
    this.onCancel,
  });
}

class FloatingProgressHud extends StatelessWidget {
  final FloatingProgressHudData data;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;
  final ReadingSettings settings;

  const FloatingProgressHud({
    super.key,
    required this.data,
    required this.settings,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final progress = data.progress;
    final hasProgress = progress != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x80000000)),
          Align(
            alignment: const Alignment(0, 0.62),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, safeBottom + 40),
              child: Container(
                width: 296,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: mutedColor.withValues(alpha: 0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: backgroundColor.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: hasProgress
                                ? CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 2.4,
                                    color: accentColor,
                                    backgroundColor: accentColor.withValues(
                                      alpha: 0.18,
                                    ),
                                  )
                                : CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: accentColor,
                                    backgroundColor: accentColor.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.title,
                                style: settings.uiText(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data.message,
                                style: settings.uiText(
                                  color: mutedColor,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (hasProgress) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: accentColor,
                          backgroundColor: accentColor.withValues(alpha: 0.16),
                        ),
                      ),
                    ],
                    if (data.onCancel != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: data.onCancel,
                          child: Text(
                            'Cancel',
                            style: settings.uiText(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
