// GENERATED from plugins.yaml by tool/build.dart. Do not edit.
//
// Which plugins a binary carries is what tells one product's binary from another's, and it
// is the one thing about this repository that is not generic. Holding it as a hand-written
// file made a tool-named repository into a product one: a second customer needed a COPY of
// the composition root, and every repair after that would land in one copy and not the other.
//
// So it is written from a manifest. A different product supplies a different plugins.yaml,
// and this file follows.
library;

import 'package:ansiwise_authentik/ansiwise_authentik.dart';
import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';
import 'package:ansiwise_core/ansiwise_core.dart';

/// Every plugin this product's binary is compiled with.
const PluginSet compiledPlugins = PluginSet(<Plugin>[
  HostPlugin(),
  KubernetesPlugin(),
  VaultPlugin(),
  VaultKubernetesPlugin(),
  HelmPlugin(),
  GitPlugin(),
  AuthentikPlugin(),
  CloudflarePlugin(),
  VersionsPlugin(),
  HeadscalePlugin(),
  HttpPlugin(),
]);
