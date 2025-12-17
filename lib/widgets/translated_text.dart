import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dreamweaver/services/translation_service.dart';

/// Displays a translated version of [text] according to current app language.
/// Falls back to the original text while translation is loading.
class TranslatedText extends StatelessWidget {
  final String text;
  final String? contextKey; // optional domain hint, e.g., 'appbar.title'
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const TranslatedText(
    this.text, {
    super.key,
    this.contextKey,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final translator = context.read<TranslationService>();
    return FutureBuilder<String>(
      future: translator.translate(text, contextKey: contextKey),
      initialData: text,
      builder: (context, snapshot) {
        final value = snapshot.data ?? text;
        return Text(
          value,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}
