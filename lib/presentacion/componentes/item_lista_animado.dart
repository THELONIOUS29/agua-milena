import 'package:flutter/material.dart';

class ItemListaAnimado extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;

  const ItemListaAnimado({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 28),
    this.duration = const Duration(milliseconds: 260),
  });

  @override
  State<ItemListaAnimado> createState() => _ItemListaAnimadoState();
}

class _ItemListaAnimadoState extends State<ItemListaAnimado>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.025, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    final cappedIndex = widget.index.clamp(0, 8);
    Future.delayed(widget.delay * cappedIndex, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }

    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(position: _slideAnim, child: widget.child),
      ),
    );
  }
}
