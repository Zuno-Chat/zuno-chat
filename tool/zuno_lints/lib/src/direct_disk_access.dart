import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'scope.dart';

const _owner = 'lib/core/files/file_system.dart';

const _entities = {'File', 'Directory', 'Link'};

const _staticHolders = {..._entities, 'FileSystemEntity', 'FileStat'};

class DirectDiskAccess extends AnalysisRule {
  static const LintCode code = LintCode(
    'direct_disk_access',
    'Disk access goes through fileSystem in $_owner.',
    correctionMessage:
        'Use fileSystem.file, fileSystem.directory or fileSystem.link, and '
        "the owner's directory lookups.",
    severity: DiagnosticSeverity.WARNING,
  );

  DirectDiskAccess()
    : super(
        name: 'direct_disk_access',
        description: 'Flags disk access in lib/ that bypasses fileSystem.',
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
    final element = node.element;
    final reaches = switch (element) {
      ConstructorElement() => false,
      TopLevelFunctionElement() => declaredIn(
        element,
        'package:path_provider/',
      ),
      ExecutableElement(isStatic: true) => isSdkClass(
        element.enclosingElement,
        'dart:io',
        _staticHolders,
      ),
      _ => false,
    };
    if (reaches) _report(node);
  }

  void _checkConstructor(AstNode node, ConstructorElement? constructor) {
    if (constructor == null) return;
    if (isSdkClass(constructor.enclosingElement, 'dart:io', _entities)) {
      _report(node);
    }
  }

  void _report(AstNode node) {
    if (!context.isInLibDir || isUnitAt(context, _owner)) return;
    rule.reportAtNode(node);
  }
}
