
from kafka import KafkaProducer

topic = 'test1.3'
brokers = 'internal-a65962cb4789511e7be2902f4cfda771-762608873.us-west-2.elb.amazonaws.com:9093'
#brokers = '10.131.207.23:30093,10.131.206.174:30093,10.131.207.46:30093'
producer = KafkaProducer(bootstrap_servers=brokers, acks='all')
for i in range(100):
    print('iteration', i)
    future = producer.send(topic, b'hello world %d' % i)
    result = future.get(timeout = 30)




