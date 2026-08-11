import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import 'home_search_field.dart';

/// Under-toolbar home strip: tabs left, optional search right.
class HomeChromeStrip extends StatelessWidget {
  const HomeChromeStrip({
    super.key,
    required this.tab,
    required this.onTab,
    required this.searchController,
    required this.searchFocus,
    required this.onQueryChanged,
    required this.onSearchSubmit,
    required this.onClearSearch,
    this.showSearch = true,
  });

  final int tab;
  final ValueChanged<int> onTab;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearchSubmit;
  final VoidCallback onClearSearch;

  /// When false, search lives in the Threads Compose row instead.
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, int i) {
      final on = tab == i;
      return GestureDetector(
        onTap: () => onTab(i),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? MutandeColors.stone800 : MutandeColors.stone500,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 2,
                width: on ? 28 : 0,
                decoration: BoxDecoration(
                  color: MutandeColors.stone800,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MutandeColors.stone50,
        border: Border(
          bottom: BorderSide(color: MutandeColors.stone200, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final searchWidth =
                (constraints.maxWidth * 0.4).clamp(180.0, 560.0);
            return Row(
              children: [
                item('Threads', 0),
                item('Network', 1),
                item('Contacts', 2),
                const Spacer(),
                if (showSearch)
                  SizedBox(
                    width: searchWidth,
                    height: 32,
                    child: HomeSearchField(
                      controller: searchController,
                      focusNode: searchFocus,
                      onChanged: onQueryChanged,
                      onSubmit: onSearchSubmit,
                      onClear: onClearSearch,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
