import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';

const reportCanvas = Color(0xFFFCF6F5);
const reportLine = Color(0xFFE6E1D8);
const reportMatchedFill = Color(0xFFE7F4E4);
const reportMatchedText = Color(0xFF2F7D32);
const reportUnmatchedFill = Color(0xFFF8E4E1);
const reportUnmatchedText = Color(0xFFB42318);

const reportMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const reportMonthsShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String reportIso(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String reportDayLabel(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')} ${reportMonthsShort[date.month - 1]} ${date.year}';
}

String reportStamp(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw.trim().isEmpty ? '—' : raw;
  final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final minute = parsed.minute.toString().padLeft(2, '0');
  final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
  return '${parsed.day} ${reportMonthsShort[parsed.month - 1]} ${parsed.year} $hour:$minute $suffix';
}

class ReportHeader extends StatelessWidget {
  const ReportHeader({
    required this.title,
    this.subtitle,
    this.onDownload,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.charcoal, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (onDownload != null)
            _IconPlate(icon: Icons.file_download_outlined, onTap: onDownload!)
          else
            const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _IconPlate extends StatelessWidget {
  const _IconPlate({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: reportLine),
          ),
          child: Icon(icon, color: AppColors.charcoal, size: 20),
        ),
      ),
    );
  }
}

class ReportIconPlate extends StatelessWidget {
  const ReportIconPlate({required this.icon, required this.onTap, super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _IconPlate(icon: icon, onTap: onTap);
}

class ReportSearch extends StatelessWidget {
  const ReportSearch({required this.controller, this.searching = false, super.key});

  final TextEditingController controller;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.charcoal, fontSize: 14),
      decoration: InputDecoration(
        hintText: AppStrings.searchReportItems,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: reportLine)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: reportLine)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.charcoal)),
      ),
    );
  }
}

class ExportBanner extends StatelessWidget {
  const ExportBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.circular(16),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF3DDC84), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.reportExported,
                style: TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
