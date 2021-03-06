#!/bin/bash
set -e

# TODO this couples too tightly to kubernetes naming convention -- move this up a level...
ID=$(hostname | awk -F'-' '{print $2}')
EXT_PORT=`expr 30093 + $ID`
NODEIP=$(dig $MY_NODE_NAME +short)
export KAFKA_ADVERTISED_LISTENERS=INTERNAL_PLAINTEXT://$(hostname).broker:9092,EXTERNAL_PLAINTEXT://$NODEIP:$EXT_PORT

if [ -z "$ID" ]; then
    ID=0
fi


if [ -z "$EXT_HOST" ]; then
    EXT_HOST=$(cat /etc/hosts | head -n1 | awk '{print $1}')
fi

: ${ZOOKEEPER:?"is not set"}

sed -r -i "s/^(broker.id)=(.*)/\1=$ID/g" /opt/kafka/config/server.properties
sed -r -i "s/^(zookeeper.connect)=(.*)/\1=$ZOOKEEPER/g" /opt/kafka/config/server.properties
sed -r -i "s/^(advertised.listeners)=(.*)/\1=PLAINTEXT:\/\/$EXT_HOST:9092/g" /opt/kafka/config/server.properties

for VAR in `env`; do
  if [[ $VAR =~ ^KAFKA_ && ! $VAR =~ ^KAFKA_(SCALA|VERSION|PORT) ]]; then
    KAFKA_PROP=`echo "$VAR" | sed -r "s/KAFKA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .`
    VAL=`echo "$VAR" | sed -r "s/(.*)=.*/\1/g"`

    echo "[config] $KAFKA_PROP=${!VAL}"

    if egrep -q "(^|^#)$KAFKA_PROP=" /opt/kafka/config/server.properties; then
      sed -r -i "s@(^|^#)($KAFKA_PROP)=(.*)@\2=${!VAL}@g" /opt/kafka/config/server.properties
    else
      echo "$KAFKA_PROP=${!VAL}" >> /opt/kafka/config/server.properties
    fi
  fi
done

echo "[start] running as broker $ID connecting to ZooKeeper $ZOOKEEPER"

# set JMX opts
if [ -z "$JMX_PORT" ]; then
    JMX_PORT=7000
fi

KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote"
KAFKA_JMX_OPTS="$KAFKA_JMX_OPTS -Dcom.sun.management.jmxremote.authenticate=false"
KAFKA_JMX_OPTS="$KAFKA_JMX_OPTS -Dcom.sun.management.jmxremote.ssl=false"
KAFKA_JMX_OPTS="$KAFKA_JMX_OPTS -Dcom.sun.management.jmxremote.port=$JMX_PORT"
KAFKA_JMX_OPTS="$KAFKA_JMX_OPTS -Dcom.sun.management.jmxremote.rmi.port=$JMX_PORT"
KAFKA_JMX_OPTS="$KAFKA_JMX_OPTS -Djava.rmi.server.hostname=${JMX_HOST:-$EXT_HOST}"
export KAFKA_JMX_OPTS

/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
