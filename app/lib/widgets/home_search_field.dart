import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mutande_macos_theme.dart';

/// Shared search pill for chrome strip and Threads Compose row.
class HomeSearchField extends StatelessWidget {
  const HomeSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmit,
    required this.onClear,
    this.hintText = 'Search threads',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: MutandeColors.stone100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused ? MutandeColors.stone800 : MutandeColors.stone200,
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
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmit(),
                  cursorColor: MutandeColors.stone800,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: MutandeColors.stone800,
                      ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.singleLineFormatter,
                  ],
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: onClear,
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
    );
  }
}
