TODO:
https://stackoverflow.com/questions/41868161/kafka-in-kubernetes-cluster-how-to-publish-consume-messages-from-outside-of-kub
https://stackoverflow.com/questions/44651219/kafka-deployment-on-minikube
https://cwiki.apache.org/confluence/display/KAFKA/KIP-103%3A+Separation+of+Internal+and+External+traffic

TODO:
- move to using as config map instead of properties in the StatefulSet?
- standardize on the pv config
- figure out if this works across faults and scaling events

# Prerequisites

- docker
- minikube started -- preferably started with ~/.minikube/config/config.json as
```
{
       "cpus": 4,
       "memory": 8000,
       "vm-driver": "xhyve"
}
```
- you can verify the minikube dashboard with
```
minikube dashboard
```
- Ensure minikube host IP starts as 192.164.64.2 (this is hard coded in a couple of places for now)
- Build a local docker image
```
# ensure in the minikube context
eval $(minikube docker-env)
cd docker-kafka-persistent
docker install -t pstg-kafka:0.10.2.0-1 .
```

# Kafka as Kubernetes StatefulSet

Example of three Kafka brokers depending on five Zookeeper instances.

To get consistent service DNS names `kafka-N.broker.kafka`(`.svc.cluster.local`), run everything in a [namespace](http://kubernetes.io/docs/admin/namespaces/walkthrough/):
```
kubectl create -f 00namespace.yml
# NOTE you might want to set 'default' context for command line
kubectl config set-context minikube --namespace=kafka
```

## (Optional) Set up volume claims

You may add [storage class](http://kubernetes.io/docs/user-guide/persistent-volumes/#storageclasses)
to the kafka StatefulSet declaration to enable automatic volume provisioning.

Alternatively create [PV](http://kubernetes.io/docs/user-guide/persistent-volumes/#persistent-volumes)s and [PVC](http://kubernetes.io/docs/user-guide/persistent-volumes/#persistentvolumeclaims)s manually. For example in Minikube.

```
./bootstrap/pv.sh
kubectl create -f ./bootstrap/pvc.yml
# check that claims are bound
kubectl get pvc
```

## Set up Zookeeper

There is a Zookeeper+StatefulSet [blog post](http://blog.kubernetes.io/2016/12/statefulset-run-scale-stateful-applications-in-kubernetes.html) and [example](https://github.com/kubernetes/contrib/tree/master/statefulsets/zookeeper),
but it appears tuned for workloads heavier than Kafka topic metadata.

The Kafka book (Definitive Guide, O'Reilly 2016) recommends that Kafka has its own Zookeeper cluster,
so we use the [official docker image](https://hub.docker.com/_/zookeeper/)
but with a [startup script change to guess node id from hostname](https://github.com/solsson/zookeeper-docker/commit/df9474f858ad548be8a365cb000a4dd2d2e3a217).

Zookeeper runs as a [Deployment](http://kubernetes.io/docs/user-guide/deployments/) without persistent storage:
```
kubectl create -f ./zookeeper/
```

If you lose your zookeeper cluster, kafka will be unaware that persisted topics exist.
The data is still there, but you need to re-create topics.

## Start Kafka

Assuming you have your PVCs `Bound`, or enabled automatic provisioning (see above), go ahead and:

```
kubectl create -f ./
```

For now we need to manually label each pod (waiting for [name in stateful set](https://github.com/kubernetes/contrib/blob/master/statefulsets/kafka/kafka.yaml)
and [here](https://github.com/kubernetes/kubernetes/issues/44103))
```
kubectl label pods kafka-0 name=kafka-0
kubectl label pods kafka-1 name=kafka-1
kubectl label pods kafka-2 name=kafka-2
```

## Testing manually

There's a Kafka pod that doesn't start the server, so you can invoke the various shell scripts.
```
kubectl create -f test/99testclient.yml
```

See `./test/test.sh` for some sample commands.

You can also download [kafkacat](https://github.com/edenhill/kafkacat) for tests from host
```
kubectl exec testclient -- ./bin/kafka-topics.sh --zookeeper zookeeper:2181 --topic test1.1.3 --create --partitions 1 --replication-factor 3
# in one terminal listen
kafkacat -C -t test1.1.3 -b 192.168.64.2:30095 -o end
# in second terminal send
kafkacat -P -t test1.1.3 -b 192.168.64.2:30093
(type in data here, it should show up in the consumer)
```
Also notice how the above example picked different brokers for the initial connection. In fact the
broker parameter can be a list of the 3 hard coded ports 30093-5

## (TODO) Automated test, while going chaosmonkey on the cluster

This is WIP, but topic creation has been automated. Note that as a [Job](http://kubernetes.io/docs/user-guide/jobs/), it will restart if the command fails, including if the topic exists :(
```
kubectl create -f test/11topic-create-test1.yml
```

Pods that keep consuming messages (but they won't exit on cluster failures)
```
kubectl create -f test/21consumer-test1.yml
```

## Teardown & cleanup

Testing and retesting... delete the namespace. PVs are outside namespaces so delete them too.
```
kubectl delete namespace kafka
# you can also remove the persistent volumes
```
