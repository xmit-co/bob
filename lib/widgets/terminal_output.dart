import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../utils/ansi_parser.dart';

/// A reusable terminal output display widget with black background and monospace font
class TerminalOutput extends StatefulWidget {
  final String output;
  final bool autoScroll;
  final Widget? placeholder;

  const TerminalOutput({
    super.key,
    required this.output,
    this.autoScroll = true,
    this.placeholder,
  });

  @override
  State<TerminalOutput> createState() => _TerminalOutputState();
}

class _TerminalOutputState extends State<TerminalOutput> {
  final ScrollController _scrollController = ScrollController();
  String? _lastOutput;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TerminalOutput oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-scroll when output changes if enabled
    if (widget.autoScroll && widget.output != _lastOutput) {
      _lastOutput = widget.output;

      // Schedule scroll after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: AppConstants.autoScrollDuration,
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: widget.output.isEmpty && widget.placeholder != null
          ? Center(child: widget.placeholder!)
          : SingleChildScrollView(
              controller: widget.autoScroll ? _scrollController : null,
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(AppConstants.rightPaneContentPadding),
              child: widget.output.isEmpty
                  ? SelectableText(
                      'Output will appear here...',
                      style: AppConstants.terminalTextStyle,
                    )
                  : SelectableText.rich(
                      TextSpan(
                        children: AnsiParser.parse(
                          widget.output,
                          defaultColor: Colors.white,
                        ),
                        style: AppConstants.terminalTextStyle,
                      ),
                    ),
            ),
    );
  }
}
