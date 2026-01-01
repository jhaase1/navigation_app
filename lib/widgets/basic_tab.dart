import 'package:flutter/material.dart';

class BasicTab extends StatefulWidget {
  final ValueNotifier<bool> rolandConnected;
  final bool mockMode;
  final ValueChanged<String> onRolandResponse;

  const BasicTab({
    super.key,
    required this.rolandConnected,
    required this.mockMode,
    required this.onRolandResponse,
  });

  @override
  State<BasicTab> createState() => _BasicTabState();
}

class _BasicTabState extends State<BasicTab> {
  @override
  void initState() {
    super.initState();
    widget.rolandConnected.addListener(_update);
  }

  @override
  void dispose() {
    widget.rolandConnected.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!widget.rolandConnected.value) return const Center(child: Text('Connect to Roland device first'));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Transitions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (widget.mockMode) {
                      widget.onRolandResponse('Mock: CUT executed');
                    } else {
                      // TODO: Implement real CUT command
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('CUT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (widget.mockMode) {
                      widget.onRolandResponse('Mock: AUTO transition executed');
                    } else {
                      // TODO: Implement real AUTO command
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('AUTO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          const Text('Program Select (PGM)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                onPressed: () {
                  if (widget.mockMode) {
                    widget.onRolandResponse('Mock: Set Program to INPUT${index + 1}');
                  } else {
                    // TODO: Implement real program select
                  }
                },
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Preview Select (PST)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ActionChip(
                label: Text('Input ${index + 1}'),
                backgroundColor: Colors.green.shade50,
                onPressed: () {
                  if (widget.mockMode) {
                    widget.onRolandResponse('Mock: Set Preview to INPUT${index + 1}');
                  } else {
                    // TODO: Implement real preview select
                  }
                },
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('Macros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              return ElevatedButton(
                onPressed: () {
                  if (widget.mockMode) {
                    widget.onRolandResponse('Mock: Executed Macro ${index + 1}');
                  } else {
                    // TODO: Implement real macro execution
                  }
                },
                child: Text('Macro ${index + 1}'),
              );
            }),
          ),
        ],
      ),
    );
  }
}