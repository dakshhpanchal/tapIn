import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/dynamic_tapin_logo.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

class HomeAppbar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppbar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // The logo sits in the leading slot so the title starts at the same
      // place as on the other tabs, and uses the same text style.
      leading: const Center(
        child: SizedBox(width: 30, height: 34, child: DynamicTapInLogo()),
      ),
      title: Text(S.of(context).appTitle),
      actions: [
        Semantics(
          identifier: 'home-my-foods',
          child: IconButton(
            tooltip: S.of(context).myFoodsLabel,
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () =>
                Navigator.of(context).pushNamed(NavigationOptions.recipesRoute),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
