from rest_framework import serializers
from . import models


class ReportSerializer(serializers.ModelSerializer):

    class Meta:
        fields = ('id', 'report_type', 'generated_at', 'data', 'cache_hit', 'generation_time_ms',)
        model = models.Report
