import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// The Markdown style of an agent's text: chat replies and pins read alike.
MarkdownStyleSheet agentMarkdownStyle(ThemeData theme) {
  final tt = theme.textTheme;
  final cs = theme.colorScheme;
  final base = tt.bodyMedium?.copyWith(height: 1.45, color: cs.onSurface);
  final mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: (base?.fontSize ?? 14) - 1,
    color: cs.onSurface,
  );
  final codeBg = cs.surfaceContainerHigh;

  return MarkdownStyleSheet(
    p: base,
    pPadding: const EdgeInsets.only(bottom: 4),
    h1: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h2: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 4),
    h3: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h4: tt.titleSmall,
    h5: tt.titleSmall,
    h6: tt.titleSmall,
    strong: const TextStyle(fontWeight: FontWeight.w700),
    em: const TextStyle(fontStyle: FontStyle.italic),
    code: mono.copyWith(backgroundColor: codeBg),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: BorderRadius.circular(8),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: cs.primary, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
    blockquote: base?.copyWith(color: cs.onSurfaceVariant),
    listBullet: base,
    listIndent: 20,
    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
    tableHead: const TextStyle(fontWeight: FontWeight.w700),
    tableCellsPadding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: cs.outlineVariant, width: 1),
      ),
    ),
  );
}
