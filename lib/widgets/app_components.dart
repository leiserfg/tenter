import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

class SectionEyebrow extends StatelessWidget {
  const SectionEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.mint,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.7,
    ),
  );
}

class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.mint),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MutedAction extends StatelessWidget {
  const MutedAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: enabled ? AppColors.mint : const Color(0xFF242A28),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Icon(icon, color: enabled ? AppColors.ink : AppColors.muted),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: enabled ? AppColors.ink : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        if (!enabled)
          const Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: AppColors.muted,
          ),
      ],
    ),
  );
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFF202622),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF333D35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.mint, size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}
