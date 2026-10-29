import 'package:flutter/material.dart';

class LoadMoreTrigger extends StatefulWidget {
  final VoidCallback onVisible;

  const LoadMoreTrigger({required this.onVisible, super.key});

  @override
  State<LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const CircularProgressIndicator();
}
