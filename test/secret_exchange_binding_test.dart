import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_cli/plugins.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

const String program = '''
name: credential-exchange
roles: [master]
steps:
  - step: vault_kv_entry_from_command
    repository: /srv/configuration
    mount: secret
    path: prod/app/service
    producer: /run/credentials.sh
    fields: [identity, api-token, other-token]
    fields_from_answers: [other-token=service_token]
    profile_path: profile.yaml
    vault_url_key: global.vaultUrl
    cluster_name_key: global.clusterName
    kubernetes_auth_path_key: global.auth
    credentials_path: credentials.txt
    kubectl: [microk8s, kubectl]
    kubectl_needs_root: true
    on_failure: exit
answers:
  - name: service_token
    kind: text
    secret: true
    required: false
    describes: The optional replacement credential, supplied in memory.
''';

void main() {
  final Registry shipped = compiledPlugins.activate(compiledPlugins.names);
  final ProgramResolver resolver = ProgramResolver(shipped);

  test('the shipped plugin set binds the private complete-entry exchange', () {
    expect(resolve(resolver, program, 'credential-exchange.yaml'), isA<ProgramResolved>());
    final RegisteredStep step = shipped.steps[const StepName('vault_kv_entry_from_command')]!;
    expect(step.source, startsWith('lib/src/steps/vault_kv_entry_from_command.dart:'));
  });

  test('a missing adapter and a misspelled exchange argument are refused', () {
    expect(
      resolve(
        const ProgramResolver(
          Registry(
            steps: <StepName, RegisteredStep>{},
            predicates: <PredicateName, RegisteredPredicate>{},
          ),
        ),
        program,
        'missing-plugin.yaml',
      ),
      isA<ProgramRefused>(),
    );
    expect(
      resolve(
        resolver,
        program.replaceFirst('fields_from_answers:', 'secret_arguments:'),
        'bad-argument.yaml',
      ),
      isA<ProgramRefused>(),
    );
    expect(resolve(resolver, program, 'innocent.yaml'), isA<ProgramResolved>());
  });
}
