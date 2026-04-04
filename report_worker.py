import json
import os
import django
import pika

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'monitoring.settings')
django.setup()

from django.conf import settings
from reports.models import Report

RABBITMQ_HOST = settings.RABBITMQ_HOST
RABBITMQ_USER = settings.RABBITMQ_USER
RABBITMQ_PASSWORD = settings.RABBITMQ_PASSWORD
EXCHANGE_NAME = 'report_pregeneration'
BINDING_KEY = 'reports.#'


def callback(ch, method, properties, body):
    message = json.loads(body)
    report_type = message.get('report_type')
    data = message.get('data', {})
    generation_time_ms = message.get('generation_time_ms', 0.0)

    report = Report(
        report_type=report_type,
        data=data,
        cache_hit=True,
        generation_time_ms=generation_time_ms,
    )
    report.save()
    print(f'[x] Saved pre-generated report: {report_type} (id={report.id})')
    ch.basic_ack(delivery_tag=method.delivery_tag)


def run():
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parameters = pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials)
    connection = pika.BlockingConnection(parameters)
    channel = connection.channel()

    channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type='topic')
    result = channel.queue_declare(queue='', exclusive=True)
    queue_name = result.method.queue

    channel.queue_bind(exchange=EXCHANGE_NAME, queue=queue_name, routing_key=BINDING_KEY)
    channel.basic_consume(queue=queue_name, on_message_callback=callback)

    print(f'[*] Worker listening on {BINDING_KEY}. Waiting for messages...')
    try:
        channel.start_consuming()
    except KeyboardInterrupt:
        print('[*] Stopping worker.')
        channel.stop_consuming()
    finally:
        connection.close()


if __name__ == '__main__':
    run()
