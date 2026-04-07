import time
import random
from django.shortcuts import render
from django.conf import settings
from django.utils import timezone
from datetime import timedelta
from .logic.logic_report import get_recent_report, create_report, get_cache_stats


def generate_report_data(report_type):
    return {
        'report_type': report_type,
        'cpu_usage': round(random.uniform(20, 90), 2),
        'memory_usage': round(random.uniform(30, 85), 2),
        'disk_io': round(random.uniform(5, 60), 2),
        'active_instances': random.randint(1, 6),
        'generated_at': timezone.now().isoformat(),
    }


def report_view(request, report_type):
    ttl = getattr(settings, 'REPORT_CACHE_TTL', 300)
    cutoff = timezone.now() - timedelta(seconds=ttl)

    recent = get_recent_report(report_type, cutoff)
    if recent:
        context = {
            'report': recent,
        }
        return render(request, 'Report/report.html', context)

    start = time.time()
    data = generate_report_data(report_type)
    generation_time_ms = (time.time() - start) * 1000

    report = create_report(report_type, data, generation_time_ms, cache_hit=False)
    context = {
        'report': report,
    }
    return render(request, 'Report/report.html', context)


def cache_stats_view(request):
    stats = get_cache_stats()
    context = {
        'stats': stats,
    }
    return render(request, 'Report/cacheStats.html', context)
