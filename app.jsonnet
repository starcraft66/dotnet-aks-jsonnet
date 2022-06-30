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
    "EventHub__Name": "something",
    "EventHub__ConsumerGroup": "something-consumer-group",
    "ServiceBus__TopicName": "sbt-something-dev-01",
    "EventHub__SubscriptionName": "sbs-something-dev-01",
  },
  keyVaults={
    'app-secrets-1': {
      'EventHub__ConnectionString': 'event-hub-connection-string',
      'ServiceBus__ConnectionString': 'service-bus-connection-string',
    }
  }
)
