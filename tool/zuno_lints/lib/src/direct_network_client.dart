import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'scope.dart';

const _owner = 'lib/core/network/app_http_client.dart';

const _httpClients = {'Client', 'IOClient'};

const _sdkHttpLibraries = {'dart:io', 'dart:_http'};

const _httpShortcuts = {
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'read',
  'readBytes',
};

class DirectNetworkClient extends AnalysisRule {
  static const LintCode code = LintCode(
    'direct_network_client',
    'HTTP clients are made by appHttpClient in $_owner.',
    correctionMessage:
        'Call appHttpClient, or take an http.Client from the caller; '
        'WebSockets go through ZunoWebSocket.',
    severity: DiagnosticSeverity.WARNING,
  );

  DirectNetworkClient()
    : super(
        name: 'direct_network_client',
        description:
            'Flags HTTP clients and WebSockets in lib/ made outside '
            'appHttpClient.',
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
      ..addInstanceCreationExpression(this, visitor)
      ..addConstructorReference(this, visitor)
      ..addSimpleIdentifier(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _checkConstructor(node, node.constructorName.element);

  @override
  void visitConstructorReference(ConstructorReference node) =>
      _checkConstructor(node, node.constructorName.element);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (isInCombinator(node)) return;
    final reaches = switch (node.element) {
      MethodElement(isStatic: true, name: 'connect', :final enclosingElement) =>
        _isSdkHttpClass(enclosingElement, 'WebSocket') ||
            (enclosingElement?.name == 'ZunoWebSocket' &&
                declaredIn(enclosingElement, 'package:zuno_http/')),
      final TopLevelFunctionElement function =>
        _httpShortcuts.contains(function.name) &&
            declaredIn(function, 'package:http/'),
      _ => false,
    };
    if (reaches) _report(node);
  }

  void _checkConstructor(AstNode node, ConstructorElement? constructor) {
    if (constructor == null) return;
    final type = constructor.enclosingElement;
    final reaches =
        _isSdkHttpClass(type, 'HttpClient') ||
        (_httpClients.contains(type.name) &&
            declaredIn(type, 'package:http/')) ||
        (type.name == 'ZunoHttpClient' &&
            declaredIn(type, 'package:zuno_http/'));
    if (reaches) _report(node);
  }

  void _report(AstNode node) {
    if (!isInLibOutside(context, _owner)) return;
    rule.reportAtNode(node);
  }
}

bool _isSdkHttpClass(Element? element, String name) =>
    _sdkHttpLibraries.any((library) => isSdkClass(element, library, {name}));
