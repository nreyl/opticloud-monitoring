import time
from django.shortcuts import render
from django.conf import settings
from django.utils import timezone
from datetime import timedelta
from measurements.models import Measurement
from .logic.logic_report import get_recent_report, create_report, get_cache_stats


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
    measurements = Measurement.objects.all().order_by('-dateTime')[:100]
    data = {
        'report_type': report_type,
        'count': measurements.count(),
        'measurements': list(measurements.values('value', 'unit', 'place')),
    }
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
