// ================================================================
// GuruSuggestionParser — extracts the [SUGGESTIONS: a | b | c] tag
// ================================================================
// NEW (CTO mandate — "Co-work Style Confirmation & Suggestions"): the
// system prompt (see GuruApiService.systemPrompt) instructs the model to
// end a reply with an optional `[SUGGESTIONS: opt one | opt two]` tag.
// This strips that tag out of the displayed text and returns the
// individual options, trimmed, so the UI can render them as tappable
// ActionChips instead of leaving the raw tag visible in the chat bubble.
class ParsedGuruReply {
  const ParsedGuruReply({required this.text, required this.suggestions});
  final String text;
  final List<String> suggestions;
}

class GuruSuggestionParser {
  static final RegExp _tag = RegExp(
    r'\[SUGGESTIONS:\s*(.*?)\]',
    caseSensitive: false,
    dotAll: true,
  );

  static ParsedGuruReply parse(String raw) {
    final match = _tag.firstMatch(raw);
    if (match == null) {
      return ParsedGuruReply(text: raw.trim(), suggestions: const []);
    }
    final optionsRaw = match.group(1) ?? '';
    final options = optionsRaw
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final cleanText = raw.replaceRange(match.start, match.end, '').trim();
    return ParsedGuruReply(text: cleanText, suggestions: options);
  }
}
