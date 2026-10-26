import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'scope.dart';

const _spanOwner = 'lib/core/async/elapsed.dart';

class DirectClockRead extends AnalysisRule {
  static const LintCode code = LintCode(
    'direct_clock_read',
    'Time is read through package:clock, so tests can drive it.',
    correctionMessage:
        'Use clock.now() for the time, and startStopwatch() from '
        '$_spanOwner for a span.',
    severity: DiagnosticSeverity.WARNING,
  );

  DirectClockRead()
    : super(
        name: 'direct_clock_read',
        description: 'Flags real-clock reads that bypass package:clock.',
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
      ..addMethodInvocation(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _check(node, node.constructorName.element);

  @override
  void visitConstructorReference(ConstructorReference node) =>
      _check(node, node.constructorName.element);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.element;
    if (method is! MethodElement || method.name != 'stopwatch') return;
    final owner = method.enclosingElement;
    if (owner?.name != 'Clock' || !declaredIn(owner, 'package:clock/')) return;
    _report(node);
  }

  void _check(AstNode node, ConstructorElement? constructor) {
    if (constructor == null || !_readsRealClock(constructor)) return;
    _report(node);
  }

  void _report(AstNode node) {
    if (!context.isInLibDir && !context.isInTestDirectory) return;
    if (isUnitAt(context, realTimeHelper) || isUnitAt(context, _spanOwner)) {
      return;
    }
    rule.reportAtNode(node);
  }
}

bool _readsRealClock(ConstructorElement constructor) {
  final type = constructor.enclosingElement;
  if (isSdkClass(type, 'dart:core', {'Stopwatch'})) return true;
  return isSdkClass(type, 'dart:core', {'DateTime'}) &&
      (constructor.name == 'now' || constructor.name == 'timestamp');
}
