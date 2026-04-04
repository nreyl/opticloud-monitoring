from ..models import Report


def get_reports(report_type):
    queryset = Report.objects.filter(report_type=report_type).order_by('-generated_at')[:10]
    return (queryset)


def get_recent_report(report_type, cutoff):
    queryset = Report.objects.filter(
        report_type=report_type,
        generated_at__gte=cutoff
    ).first()
    return (queryset)


def create_report(report_type, data, generation_time_ms, cache_hit=False):
    report = Report(
        report_type=report_type,
        data=data,
        cache_hit=cache_hit,
        generation_time_ms=generation_time_ms,
    )
    report.save()
    return (report)


def get_cache_stats():
    total = Report.objects.count()
    hits = Report.objects.filter(cache_hit=True).count()
    misses = total - hits
    hit_rate = (hits / total * 100) if total > 0 else 0
    return ({
        'total': total,
        'hits': hits,
        'misses': misses,
        'hit_rate_percent': round(hit_rate, 2),
    })
