local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.24/main.libsonnet';
local deploy = k.apps.v1.deployment;
local deploySpec = k.apps.v1.deployment.spec.template.spec;
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;
local envFromSource = k.core.v1.envFromSource;
local configMap = k.core.v1.configMap;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;
local ingress = k.networking.v1.ingress;
local ingressTLS = k.networking.v1.ingressTLS;
local ingressRule = k.networking.v1.ingressRule;
local volumeMount = k.core.v1.volumeMount;
local nodeAffinity = k.core.v1.nodeAffinity;
local nodeSelector = k.core.v1.nodeSelector;
local nodeSelectorTerm = k.core.v1.nodeSelectorTerm;

local withoutNameAnnotation = {
  // Removes the default kubernetes `name` selector because
  // we use the more idiomatic `app.kubernetes.io/name` instead
  // Doesn't technically remove it but hides it from the output
  spec+: {
    selector+: {
      matchLabels+: {
        name:: super.name,
      },
    },
    template+: {
      metadata+: {
        labels+: {
          name:: super.name,
        },
      },
    },
  },
};

# app identity is a magic constant, we should pass it via TLA later
local azureKeyVaultSecretProviderClass(keyVault, usePodIdentity='false', useVMManagedIdentity='true', userAssignedIdentityID='', tenant='') = {
  apiVersion: 'secrets-store.csi.x-k8s.io/v1',
  kind: 'SecretProviderClass',
  metadata: {
    name: 'azure-key-vault-' + keyVault.name,
  },
  spec: {
    provider: 'azure',
    secretObjects: [{
      data: [
        {
          key: secret.name,
          objectName: secret.name,
        }
        for secret in keyVault.secrets
      ],
      secretName: keyVault.k8sSecretName,
      type: 'Opaque',
    }],
    parameters: {
      usePodIdentity: usePodIdentity,
      useVMManagedIdentity: useVMManagedIdentity,
      userAssignedIdentityID: userAssignedIdentityID,
      keyvaultName: keyVault.name,
      tenantId: tenant,
      # whack shit required for
      # https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/getting-started/usage/#create-your-own-secretproviderclass-object
      objects: "array:\n" + std.join("", [
          "  - |\n    objectName: " + secret.nameInKeyVault
          + "\n    objectAlias: " + secret.name
          + "\n    objectType: secret"
          + "\n    objectVersion: \"\"\n"
        for secret in keyVault.secrets
      ]),
    },
  },
};

local csiKeyVaultVolumes(keyVaults) = {
  spec+: {
    template+: {
      spec+: {
        volumes+: [
          {
            name: 'azure-key-vault-' + kv.name,
            csi: {
              driver: 'secrets-store.csi.k8s.io',
              readOnly: true,
              volumeAttributes: {
                secretProviderClass: 'azure-key-vault-' + kv.name,
              },
            },
          }
          for kv in keyVaults
        ],
      },
    },
  },
};

local mkSecret(secretName, nameInKeyVault) =
  {
    name: secretName,
    nameInKeyVault: nameInKeyVault,
  };

local mkKeyVault(name, secrets={}) =
  {
    name: name,
    secrets: std.map(function(key) mkSecret(secretName=key, nameInKeyVault=secrets[key]), std.objectFields(secrets)),
    k8sSecretName: 'azure-key-vault-' + name,
  };

{
  mkDotnetApplication(name, image, config, keyVaults, replicas, web, nodePool=''):
    {
      // Stupidity because std.mapWithKeys returns some object with original keys and not an array like you'd expect a map to
      // A quick search reveals I'm not the only one to complain about this... oh well. Here's the workaround
      // https://github.com/google/jsonnet/issues/543
      keyVaultObjects:: std.map(function(key) mkKeyVault(key, keyVaults[key]), std.objectFields(keyVaults)),
      apiVersion: 'v1',
      kind: 'List',
      items:
        [
          deploy.new(name=name, containers=[
            container.new(name=name, image=image)
            + container.withEnvFromMixin([
              envFromSource.secretRef.withName(kv.k8sSecretName)
              for kv in self.keyVaultObjects
            ])
            + container.withVolumeMountsMixin([
              volumeMount.new(kv.k8sSecretName, '/mnt/secrets-' + kv.name, true)
              for kv in self.keyVaultObjects
            ])
            + container.withEnvFromMixin(envFromSource.configMapRef.withName(name + '-config'))
            + container.withPortsMixin([
              containerPort.newNamed(80, 'http'),
            ]),
            container.new(name='dotnet-monitor', image='mcr.microsoft.com/dotnet/monitor:6.0.0'),
          ], replicas=replicas, podLabels={ 'app.kubernetes.io/name': name })
          + withoutNameAnnotation
          + (if nodePool != '' then deploy.spec.template.spec.withNodeSelectorMixin(
              {'kubernetes.azure.com/agentpool': 'default'}
            ) else {})
          + csiKeyVaultVolumes(self.keyVaultObjects),
        ]
        + [
          configMap.new(name + '-config', config),
        ]
        + [
          azureKeyVaultSecretProviderClass(kv)
          for kv in self.keyVaultObjects
        ]
        + [
          service.new(name, {
            'app.kubernetes.io/name': name,
          }, [
            servicePort.new(80, 'http'),
          ]),
        ]
        + if web.enabled then [
          ingress.new(name)
          + ingress.metadata.withAnnotations({
            'cert-manager.io/cluster-issuer': 'letsencrypt-prod',
          })
          + ingress.spec.withIngressClassName('ingress-nginx')
          + ingress.spec.withRulesMixin([
            ingressRule.withHost(host)
            for host in web.hosts
          ])
          + if web.tls then ingress.spec.withTls(
            ingressTLS.withHosts(web.hosts)
            + ingressTLS.withSecretName(std.strReplace(web.hosts[0] + '-tls', '.', '-'))
          ) else {},
        ] else [],
    },
}
