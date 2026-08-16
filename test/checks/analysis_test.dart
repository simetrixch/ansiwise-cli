import 'package:ansiwise_checks_tree/audits.dart';

/// analysis — the analyzer and the formatter are clean over this package's own tree.
///
/// This repository holds the gate that runs both tools over every package it walks, and it walks
/// this one. That is not the same statement. The gate is one program somebody has to start; this is
/// a check the suite carries, so it answers under a plain `dart test`, and so `declared-checks`
/// reports it the day somebody deletes it. A gate that is not held to what it holds others to is a
/// gate nobody can point at.
void main() => auditAnalysis();
