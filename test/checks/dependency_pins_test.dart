import 'package:ansiwise_checks_tree/audits.dart';

/// dependency-pins — every dependency this package resolves out of git names a release tag.
///
/// THIS IS THE TREE THE CHECK EXISTS FOR. Fourteen of this package's dependencies are resolved out
/// of git — the framework, eleven plugins, and the two check libraries — and none of them produces
/// a file: whoever resolves one gets the tree standing at the ref it names. A ref naming a branch
/// therefore hands this binary a different framework the next time anybody pushes, under the same
/// name, with nothing in the resolution to notice it by. The binary that is compiled from here is
/// the one place that reaches every package of the family at once, so a branch ref here is the
/// widest one there is.
///
/// WHY IT COULD NOT BE SWITCHED ON BEFORE. Until each of those repositories had cut a release there
/// was no tag to name, and a check demanding one would have refused this tree for a state nobody
/// could leave. It goes on in the same act that pins the fourteen, which is the only order in which
/// it is ever green.
void main() => auditDependencyPins();
