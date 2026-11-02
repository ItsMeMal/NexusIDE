import 'package:flutter/material.dart';
import 'ai_agent_proposals.dart';

const _reviewPanel = Color(0xFF111821);
const _reviewBg = Color(0xFF0D1117);
const _reviewBorder = Color(0xFF243140);
const _reviewText = Color(0xFFE6EDF3);
const _reviewMuted = Color(0xFF8B98A9);
const _reviewAccent = Color(0xFF62D3CE);

class AiAgentReviewDialog extends StatelessWidget {
  const AiAgentReviewDialog({required this.changes, super.key});
  final List<AiAgentProposedChange> changes;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _reviewPanel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Review proposed changes', style: TextStyle(color: _reviewText, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(changes.length.toString() + ' file(s). Nothing is written until you apply.', style: const TextStyle(color: _reviewMuted, fontSize: 12)),
            const SizedBox(height: 10),
            Expanded(child: ListView.separated(
              itemCount: changes.length,
              separatorBuilder: (_, __) => const Divider(color: _reviewBorder, height: 1),
              itemBuilder: (context, index) {
                final item = changes[index];
                return ExpansionTile(
                  initiallyExpanded: index == 0,
                  title: Text(item.path, style: const TextStyle(color: _reviewText, fontSize: 12, fontFamily: 'Consolas')),
                  subtitle: Text(item.isNew ? 'NEW FILE' : 'MODIFIED', style: const TextStyle(color: _reviewMuted, fontSize: 9)),
                  children: [SizedBox(height: 240, child: Row(children: [
                    Expanded(child: _content('CURRENT', item.oldContent ?? '(new file)', const Color(0xFFFFA7AE))),
                    const VerticalDivider(width: 1, color: _reviewBorder),
                    Expanded(child: _content('PROPOSED', item.newContent, const Color(0xFF9AE6B4))),
                  ]))],
                );
              },
            )),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Apply reviewed changes'),
                style: FilledButton.styleFrom(backgroundColor: _reviewAccent, foregroundColor: _reviewBg),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _content(String title, String content, Color foreground) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(color: _reviewBg, padding: const EdgeInsets.all(6), child: Text(title, style: TextStyle(color: foreground, fontSize: 10, fontWeight: FontWeight.w700))),
      Expanded(child: Container(
        color: _reviewBg,
        child: Scrollbar(child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: SelectableText(content, style: TextStyle(color: foreground, fontFamily: 'Consolas', fontSize: 10, height: 1.4)),
        )),
      )),
    ]);
  }
}
