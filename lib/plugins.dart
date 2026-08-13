import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';

/// Every plugin this product's binary is compiled with.
const PluginSet compiledPlugins = PluginSet(<Plugin>[
  HostPlugin(),
  KubernetesPlugin(),
  VaultPlugin(),
  VaultKubernetesPlugin(),
  HelmPlugin(),
  GitPlugin(),
]);
