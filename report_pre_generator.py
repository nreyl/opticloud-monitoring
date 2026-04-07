import json
import time
import os
import random
import django
import pika

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'monitoring.settings')
django.setup()

from django.conf import settings
from django.utils import timezone

RABBITMQ_HOST = settings.RABBITMQ_HOST
RABBITMQ_USER = settings.RABBITMQ_USER
RABBITMQ_PASSWORD = settings.RABBITMQ_PASSWORD
EXCHANGE_NAME = 'report_pregeneration'
REPORT_TYPES = ['daily_summary', 'weekly_summary', 'resource_usage']
INTERVAL_SECONDS = 30


def generate_report_data(report_type):
    start = time.time()
    data = {
        'report_type': report_type,
        'cpu_usage': round(random.uniform(20, 90), 2),
        'memory_usage': round(random.uniform(30, 85), 2),
        'disk_io': round(random.uniform(5, 60), 2),
        'active_instances': random.randint(1, 6),
        'generated_at': timezone.now().isoformat(),
    }
    elapsed_ms = (time.time() - start) * 1000
    return data, elapsed_ms


def connect():
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parameters = pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials)
    connection = pika.BlockingConnection(parameters)
    channel = connection.channel()
    channel.exchange_declare(exchange=EXCHANGE_NAME, exchange_type='topic')
    return connection, channel


def publish_report(channel, report_type, data, generation_time_ms):
    routing_key = f'reports.pregenerate.{report_type}'
    message = {
        'report_type': report_type,
        'data': data,
        'generation_time_ms': generation_time_ms,
        'generated_at': time.time(),
    }
    channel.basic_publish(
        exchange=EXCHANGE_NAME,
        routing_key=routing_key,
        body=json.dumps(message),
    )
    print(f'[x] Published {routing_key} ({generation_time_ms:.2f}ms)')


def run():
    connection, channel = connect()
    print('[*] Pre-generator running. Sending reports every 30 seconds.')
    try:
        while True:
            for report_type in REPORT_TYPES:
                data, elapsed_ms = generate_report_data(report_type)
                publish_report(channel, report_type, data, elapsed_ms)
            time.sleep(INTERVAL_SECONDS)
    except KeyboardInterrupt:
        print('[*] Stopping pre-generator.')
    finally:
        connection.close()


if __name__ == '__main__':
    run()
