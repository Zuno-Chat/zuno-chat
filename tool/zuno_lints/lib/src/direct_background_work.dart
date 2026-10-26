import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'scope.dart';

const _owner = 'lib/core/async/background_work.dart';

const _isolateStarters = {'run', 'spawn', 'spawnUri'};

class DirectBackgroundWork extends AnalysisRule {
  static const LintCode code = LintCode(
    'direct_background_work',
    'Isolates are started through runInBackground in $_owner.',
    correctionMessage:
        'Call runInBackground, or hand computeInBackground to the SDK.',
    severity: DiagnosticSeverity.WARNING,
  );

  DirectBackgroundWork()
    : super(
        name: 'direct_background_work',
        description: 'Flags isolates in lib/ started outside runInBackground.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addSimpleIdentifier(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (isInCombinator(node)) return;
    if (!_startsIsolate(node.element)) return;
    if (!context.isInLibDir || isUnitAt(context, _owner)) return;
    rule.reportAtNode(node);
  }
}

bool _startsIsolate(Element? element) => switch (element) {
  MethodElement(isStatic: true, :final name) =>
    _isolateStarters.contains(name) &&
        isSdkClass(element.enclosingElement, 'dart:isolate', {'Isolate'}),
  TopLevelFunctionElement(name: 'compute') => declaredIn(
    element,
    'package:flutter/',
  ),
  _ => false,
};
