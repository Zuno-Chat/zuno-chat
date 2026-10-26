import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

const realTimeHelper = 'test/helpers/pump_until.dart';

bool isUnitAt(RuleContext context, String relativePath) {
  final root = context.package?.root;
  if (root == null) return false;
  final paths = root.provider.pathContext;
  final unit = context.currentUnit ?? context.definingUnit;
  return paths.equals(
    unit.file.path,
    paths.joinAll([root.path, ...relativePath.split('/')]),
  );
}

bool declaredIn(Element? element, String uriPrefix) =>
    element?.library?.uri.toString().startsWith(uriPrefix) ?? false;

bool isSdkClass(Element? element, String library, Set<String> names) =>
    element is InterfaceElement &&
    element.library.uri.toString() == library &&
    names.contains(element.name);

bool isInCombinator(AstNode node) => node.parent is Combinator;
