import 'package:flutter/material.dart';
import 'chats_overview_screen.dart';
import 'model_library_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

/// Home destinations are mounted only when first opened; conversations use their own route.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selected = 0;
  final _visited = <int>{0};
  static const _labels = ['Chats', 'Models', 'Saved', 'Settings'];
  static const _icons = [
    Icons.chat_bubble_outline,
    Icons.memory_outlined,
    Icons.bookmarks_outlined,
    Icons.settings_outlined,
  ];
  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selected = index;
      _visited.add(index);
    });
  }

  Widget _destination(int index) => switch (index) {
    0 => ChatsOverviewScreen(active: _selected == 0),
    1 => const ModelLibraryScreen(),
    2 => const SavedScreen(),
    _ => const SettingsScreen(),
  };
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      final content = IndexedStack(
        index: _selected,
        children: [
          for (var index = 0; index < _labels.length; index++)
            _visited.contains(index)
                ? TickerMode(
                    enabled: index == _selected,
                    child: _destination(index),
                  )
                : const SizedBox.shrink(),
        ],
      );
      return Scaffold(
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _selected,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (var index = 0; index < _labels.length; index++)
                        NavigationRailDestination(
                          icon: Icon(_icons[index]),
                          label: Text(_labels[index]),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _selected,
                onDestinationSelected: _select,
                destinations: [
                  for (var index = 0; index < _labels.length; index++)
                    NavigationDestination(
                      icon: Icon(_icons[index]),
                      label: _labels[index],
                    ),
                ],
              ),
      );
    },
  );
}
