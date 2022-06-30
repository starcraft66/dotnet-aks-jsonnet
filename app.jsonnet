local lib = import 'lib/dotnetapp.libsonnet';

function(tag='latest') lib.mkDotnetApplication(
  name='sample-function-app',
  image='myregistry.azurecr.io/samples/dotnet:' + tag,
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
  keyVaults={
    'app-secrets-1': [
      'username',
      'password',
    ],
    'app-secrets-2': [
      'username',
      'password',
    ],
  }
)
