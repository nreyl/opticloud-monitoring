from django.db import models


class Report(models.Model):
    report_type = models.CharField(max_length=100)
    generated_at = models.DateTimeField(auto_now_add=True)
    data = models.JSONField()
    cache_hit = models.BooleanField(default=False)
    generation_time_ms = models.FloatField(default=0.0)

    def __str__(self):
        return '%s %s' % (self.report_type, self.generated_at)
