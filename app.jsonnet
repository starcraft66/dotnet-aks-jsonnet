local lib = import "lib/dotnetapp.libsonnet";

lib.mkDotnetApplication(
  name='sample-function-app',
  image='myregistry.azurecr.io/samples/dotnet:v2022-01-22',
  replicas=3,
  web={
    enabled: true,
    tls: true,
    hosts: [
      'www.example.com',
      'www2.example.com',
    ],
  },
  config={
    key: 'value',
  },
  keyVaults=[
    lib.mkKeyVault(
      name='app-secrets-1',
      secrets=[
        'username',
        'password',
      ],
    ),
    lib.mkKeyVault(
      name='app-secrets-2',
      secrets=[
        'username',
        'password',
      ],
    ),
  ]
)
