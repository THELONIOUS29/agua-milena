import 'package:flutter/material.dart';

/// Mantiene una altura estable al distribuir las tarjetas del inicio.
class GrillaInicio extends StatelessWidget {
  final List<Widget> children;

  const GrillaInicio({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 600
            ? 3
            : constraints.maxWidth >= 300
            ? 2
            : 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 216,
        children: children,
      ),
    );
  }
}
