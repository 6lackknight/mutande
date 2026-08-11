import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mutande_macos_theme.dart';

/// Under-toolbar home strip: tabs left, search right (~40% of strip width).
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
  });

  final int tab;
  final ValueChanged<int> onTab;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearchSubmit;
  final VoidCallback onClearSearch;

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
            final searchWidth = (constraints.maxWidth * 0.4).clamp(180.0, 560.0);
            return Row(
              children: [
                item('Threads', 0),
                item('Network', 1),
                item('Contacts', 2),
                const Spacer(),
                SizedBox(
                  width: searchWidth,
                  height: 32,
                  child: ListenableBuilder(
                    listenable:
                        Listenable.merge([searchController, searchFocus]),
                    builder: (context, _) {
                      final focused = searchFocus.hasFocus;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: MutandeColors.stone100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: focused
                                ? MutandeColors.stone800
                                : MutandeColors.stone200,
                            width: focused ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.search,
                              size: 15,
                              color: MutandeColors.stone400,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                focusNode: searchFocus,
                                onChanged: onQueryChanged,
                                onSubmitted: (_) => onSearchSubmit(),
                                cursorColor: MutandeColors.stone800,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: MutandeColors.stone800,
                                    ),
                                decoration: const InputDecoration(
                                  hintText: 'Search threads',
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 7),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter
                                      .singleLineFormatter,
                                ],
                              ),
                            ),
                            if (searchController.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Clear',
                                onPressed: onClearSearch,
                                icon: const Icon(Icons.close, size: 14),
                                color: MutandeColors.stone400,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
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
