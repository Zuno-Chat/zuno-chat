import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

class HardcodedUserText extends AnalysisRule {
  static const LintCode code = LintCode(
    'hardcoded_user_text',
    'User-facing text must come from lib/l10n/app_en.arb.',
    correctionMessage:
        'Add a key to app_en.arb and read it through context.l10n.',
    severity: DiagnosticSeverity.WARNING,
  );

  HardcodedUserText()
    : super(
        name: 'hardcoded_user_text',
        description: 'Flags literal text passed where users see it.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addSimpleStringLiteral(this, visitor)
      ..addStringInterpolation(this, visitor);
  }
}

const _technical = {
  'assetName',
  'debugLabel',
  'fontFamily',
  'groupValue',
  'heroTag',
  'id',
  'identifier',
  'initialRoute',
  'package',
  'restorationId',
  'restorationScopeId',
  'routeName',
  'semanticsIdentifier',
  'src',
  'tag',
  'uri',
  'url',
  'userAgentPackageName',
};

const _technicalFlutter = {
  'Image': {'name'},
  'CheckedPopupMenuItem': {'value'},
  'DropdownButton': {'value'},
  'DropdownMenuItem': {'value'},
  'PopupMenuItem': {'value'},
  'Radio': {'value'},
  'RadioListTile': {'value'},
  'RadioMenuButton': {'value'},
};

const _sinks = {
  'package:flutter/': {
    'InputDecoration': {
      'labelText',
      'hintText',
      'helperText',
      'errorText',
      'prefixText',
      'suffixText',
      'counterText',
      'semanticCounterText',
    },
    'TextSpan': {'text', 'semanticsLabel'},
    'BottomNavigationBarItem': {'label', 'tooltip'},
  },
  'package:flutter_local_notifications': {
    'AndroidNotificationChannel': {'name', 'description'},
    'AndroidNotificationChannelGroup': {'name', 'description'},
    'AndroidNotificationDetails': {
      'channelName',
      'channelDescription',
      'ticker',
      'subText',
    },
    'AndroidNotificationAction': {'title'},
    'AndroidNotificationActionInput': {'label'},
    'DarwinNotificationAction': {'title', 'buttonTitle', 'placeholder'},
    'BigTextStyleInformation': {'bigText', 'contentTitle', 'summaryText'},
    'InboxStyleInformation': {'contentTitle', 'summaryText'},
    'MessagingStyleInformation': {'conversationTitle'},
    'Person': {'name'},
    'Message': {'text'},
    'FlutterLocalNotificationsPlugin': {'title', 'body'},
  },
  'package:share_plus': {
    'ShareParams': {'subject', 'title'},
  },
  'package:file_picker': {
    'FilePicker': {'dialogTitle'},
  },
};

final _letter = RegExp(r'\p{L}', unicode: true);

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      _check(node, node.value);

  @override
  void visitStringInterpolation(StringInterpolation node) => _check(
    node,
    node.elements.whereType<InterpolationString>().map((e) => e.value).join(),
  );

  void _check(StringLiteral node, String text) {
    if (!context.isInLibDir || !_letter.hasMatch(text)) return;
    final parameter = _carryingParameter(node);
    if (parameter == null || !_isDisplaySink(parameter)) return;
    rule.reportAtNode(node);
  }
}

FormalParameterElement? _carryingParameter(StringLiteral literal) {
  Expression current = literal;
  while (true) {
    switch (current.parent) {
      case final AdjacentStrings next:
        current = next;
      case final ParenthesizedExpression next:
        current = next;
      case final NamedArgument named:
        return named.correspondingParameter;
      case final BinaryExpression next
          when next.operator.lexeme == '??' || next.operator.lexeme == '+':
        current = next;
      case final ConditionalExpression next when next.condition != current:
        current = next;
      case SwitchExpressionCase(
            :final expression,
            parent: final SwitchExpression next,
          )
          when expression == current:
        current = next;
      case ArgumentList():
        return current.correspondingParameter;
      default:
        return null;
    }
  }
}

bool _isDisplaySink(FormalParameterElement parameter) {
  if (parameter.metadata.annotations.any(
    (a) => a.element?.name == 'displayText',
  )) {
    return true;
  }
  if (!parameter.type.isDartCoreString) return false;
  final owner = parameter.enclosingElement;
  final type = switch (owner) {
    ConstructorElement(:final enclosingElement) => enclosingElement,
    MethodElement(:final enclosingElement) => enclosingElement,
    _ => null,
  };
  if (type is! InterfaceElement) return false;
  final name = parameter.name ?? '';
  final uri = type.library.uri.toString();
  for (final MapEntry(key: prefix, value: classes) in _sinks.entries) {
    final names = classes[type.name];
    if (names != null && uri.startsWith(prefix)) return names.contains(name);
  }
  return owner is ConstructorElement &&
      _isWidget(type) &&
      !_technical.contains(name) &&
      !(uri.startsWith('package:flutter/') &&
          (_technicalFlutter[type.name]?.contains(name) ?? false));
}

bool _isWidget(InterfaceElement type) =>
    [type.thisType, ...type.allSupertypes].any(
      (t) =>
          t.element.name == 'Widget' &&
          t.element.library.uri.toString().startsWith('package:flutter/'),
    );
