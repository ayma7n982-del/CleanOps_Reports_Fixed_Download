import 'package:flutter/material.dart';

import '../../core/services/trip_dumpsite.dart';
import '../../core/localization.dart';

class TripDumpsitePicker extends StatelessWidget {
  final List<TripDumpsite> sites;
  final String? selectedId;
  final bool enabled, loading, fromCache;
  final String? error;
  final ValueChanged<String> onSelected;
  final VoidCallback onRetry;

  const TripDumpsitePicker({
    super.key,
    required this.sites,
    required this.selectedId,
    required this.enabled,
    required this.loading,
    required this.fromCache,
    required this.error,
    required this.onSelected,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final selected = sites.where((s) => s.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: enabled && !loading && error == null && sites.isNotEmpty
              ? () => _choose(context)
              : null,
          icon: const Icon(Icons.location_on_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                AppText(
                  selected?.name ?? 'اختر المكب / نقطة التجميع',
                  textAlign: TextAlign.center,
                ),
                if (selected != null && selected.location.isNotEmpty)
                  AppText(
                    selected.location,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          AppText(error!),
          TextButton(
            onPressed: enabled ? onRetry : null,
            child: const AppText('إعادة تحميل المكبات'),
          ),
        ] else if (!loading && sites.isEmpty)
          AppText(
            fromCache
                ? 'لا توجد مكبات محفوظة على الجهاز. اتصل بالإنترنت لتحميلها أول مرة.'
                : 'لا توجد مكبات متاحة. يُرجى إضافتها من إدارة المكبات.',
          ),
        if (fromCache && sites.isNotEmpty && error == null)
          const AppText(
            'تعرض المكبات المحفوظة على الجهاز؛ تُحدّث تلقائيًا عند الاتصال.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  Future<void> _choose(BuildContext context) async {
    var search = '';
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .6,
            child: Column(
              children: [
                const AppText('اختر المكب / نقطة التجميع'),
                TextField(
                  onChanged: (v) =>
                      update(() => search = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    labelText: 'ابحث باسم المكب أو موقعه',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final filtered = sites
                          .where(
                            (s) => '${s.name} ${s.location}'
                                .toLowerCase()
                                .contains(search),
                          )
                          .toList();
                      if (filtered.isEmpty)
                        return const Center(child: AppText('لا توجد نتائج.'));
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final site = filtered[i];
                          return ListTile(
                            title: AppText(site.name),
                            subtitle: site.location.isEmpty
                                ? null
                                : AppText(site.location),
                            selected: site.id == selectedId,
                            trailing: site.id == selectedId
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(context, site.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (id != null) onSelected(id);
  }
}
