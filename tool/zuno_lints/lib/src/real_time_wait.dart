import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'scope.dart';

const _testApis = [
  'package:flutter_test/',
  'package:test/',
  'package:test_api/',
  'package:test_core/',
];

const _realTimeCallbacks = {
  'test',
  'setUp',
  'setUpAll',
  'tearDown',
  'tearDownAll',
};

class RealTimeWait extends AnalysisRule {
  static const LintCode code = LintCode(
    'real_time_wait',
    'A test never waits on real time.',
    correctionMessage:
        'Await the work itself, or wait with pumpUntil on a condition.',
    severity: DiagnosticSeverity.WARNING,
  );

  RealTimeWait()
    : super(
        name: 'real_time_wait',
        description: 'Flags Future.delayed waits that run on the real clock.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this, context));
  }
}

enum _Time { real, realTest, fake, unknown }

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    if (constructor == null || constructor.name != 'delayed') return;
    if (!isSdkClass(constructor.enclosingElement, 'dart:async', {'Future'})) {
      return;
    }
    if (!context.isInTestDirectory || isUnitAt(context, realTimeHelper)) {
      return;
    }
    final waitsOnRealTime = switch (_timeAround(node)) {
      _Time.real => true,
      _Time.realTest => !_isZero(
        node.argumentList.arguments.firstOrNull?.argumentExpression,
      ),
      _Time.fake || _Time.unknown => false,
    };
    if (waitsOnRealTime) rule.reportAtNode(node);
  }
}

_Time _timeAround(AstNode node) {
  for (AstNode? at = node.parent; at != null; at = at.parent) {
    if (at is! FunctionExpression) continue;
    final argument = at.parent is NamedArgument ? at.parent : at;
    final call = argument?.parent?.parent;
    if (argument?.parent is! ArgumentList || call is! MethodInvocation) {
      continue;
    }
    final time = _timeOf(call.methodName.element);
    if (time != _Time.unknown) return time;
  }
  return _Time.unknown;
}

_Time _timeOf(Element? callee) {
  final name = callee?.name;
  if (declaredIn(callee, 'package:flutter_test/')) {
    if (name == 'runAsync') return _Time.real;
    if (name == 'testWidgets') return _Time.fake;
  }
  if (declaredIn(callee, 'package:fake_async/') &&
      (name == 'fakeAsync' || name == 'run')) {
    return _Time.fake;
  }
  if (_realTimeCallbacks.contains(name) &&
      _testApis.any((api) => declaredIn(callee, api))) {
    return _Time.realTest;
  }
  return _Time.unknown;
}

bool _isZero(Expression? duration) => switch (duration?.unParenthesized) {
  PrefixedIdentifier(:final prefix, :final identifier) =>
    identifier.name == 'zero' &&
        isSdkClass(prefix.element, 'dart:core', {'Duration'}),
  InstanceCreationExpression(:final constructorName, :final argumentList) =>
    isSdkClass(constructorName.element?.enclosingElement, 'dart:core', {
          'Duration',
        }) &&
        argumentList.arguments.every(
          (argument) =>
              argument is NamedArgument &&
              argument.argumentExpression is IntegerLiteral &&
              (argument.argumentExpression as IntegerLiteral).value == 0,
        ),
  _ => false,
};
